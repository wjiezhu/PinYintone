import XCTest
@testable import PinYintone

/// 录音来源的替身：把一段合成的声音同步推给练习逻辑。
/// 不碰麦克风、不弹权限框，所以这组测试在任何模拟器上结果都一样。
@MainActor
final class FakeRecorder: RecordingSource {
    var onChunk: (([Int16]) -> Void)?
    var onFinish: (([Int16]) -> Void)?
    var startError: Error?
    private(set) var isRunning = false
    private(set) var startCount = 0
    private var produced: [Int16] = []

    func start(duration: TimeInterval?) throws {
        if let startError { throw startError }
        isRunning = true
        startCount += 1
        produced = []
    }

    @discardableResult
    func stop() -> [Int16] {
        isRunning = false
        let buffer = produced
        onFinish?(buffer)
        return buffer
    }

    /// 基频按给定声调的理想轮廓变化的一段声音
    func speak(tones: [Int], seconds: Double = 0.9) {
        let rate = 16_000.0
        let contour = ToneContour.ideal(for: tones).map(Double.init)
        let total = Int(seconds * rate)
        var phase = 0.0
        var samples = [Int16](repeating: 0, count: total)
        for n in 0..<total {
            let pos = Double(n) / Double(total) * Double(contour.count - 1)
            let lo = Int(pos), hi = min(lo + 1, contour.count - 1)
            let hz = contour[lo] + (contour[hi] - contour[lo]) * (pos - Double(lo))
            phase += 2 * Double.pi * hz / rate
            samples[n] = Int16(sin(phase) * 9000)
        }
        push(samples)
    }

    /// 一段静音：没有任何有声帧
    func silence(seconds: Double = 0.6) {
        push([Int16](repeating: 0, count: Int(seconds * 16_000)))
    }

    private func push(_ samples: [Int16]) {
        produced.append(contentsOf: samples)
        var i = 0
        while i < samples.count {
            onChunk?(Array(samples[i..<min(i + 1600, samples.count)]))
            i += 1600
        }
    }
}

/// 声调练习：没有强制阶段、状态机、每次录音一个新尝试、自测不给评价
/// （需求 R06 / R07 / U03，验收 A07、A09、A14、A17、A18）。
@MainActor
final class TonePracticeTests: XCTestCase {

    private var recorder: FakeRecorder!
    private var vm: ToneTrainingViewModel!
    private var savedDefaults: [String: Any?] = [:]
    private let touchedKeys = ["pt_tone_attempts", "pt_tone_practice_cursor", "pt_tone_phase",
                               "pt_tone_cursor_pretest", "pt_tone_cursor_training"]

    override func setUp() {
        super.setUp()
        for key in touchedKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        StubURLProtocol.install()               // 不联网
        ResearchTestSupport.enrolledAccount()
        recorder = FakeRecorder()
        vm = ToneTrainingViewModel(sequencer: ToneSequencer(), recorder: recorder)
        vm.loadCurrent()
    }

    override func tearDown() {
        vm = nil
        recorder = nil
        LearnerRecordingStore.shared.clear()
        for key in touchedKeys {
            if let value = savedDefaults[key] ?? nil {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    /// 让帧化 → 提基频的异步任务跑完
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    /// 录一次：`matching` 为 true 时念对目标声调，否则念成别的调
    private func record(matching: Bool = true) async {
        vm.startRecording()
        let target = vm.currentLexeme?.tones ?? [1]
        recorder.speak(tones: matching ? target : target.map { $0 == 4 ? 2 : 4 })
        await settle()
        vm.stopRecordingAndEvaluate()
    }

    private var attempts: [ResearchAttemptRecord] { ResearchAttemptLog.shared.pending }
    private func events(_ name: ResearchEventName) -> [ResearchEvent] {
        ResearchEventLog.shared.pending.filter { $0.name == name }
    }

    // MARK: - 没有强制阶段（R06 / A07）

    /// 打开就是普通练习：有词可练、能录音、显示反馈，没有任何前置门槛
    func testPracticeIsAvailableImmediately() {
        XCTAssertEqual(vm.mode, .practice)
        XCTAssertNotNil(vm.currentLexeme)
        XCTAssertEqual(vm.stage, .ready)
        XCTAssertTrue(vm.canRecord)
    }

    /// 已安装用户升级后：旧版存下的「前测」阶段与游标不再挡路
    func testLegacyPretestStateIsIgnoredAfterUpgrade() {
        UserDefaults.standard.set("pretest", forKey: "pt_tone_phase")
        UserDefaults.standard.set(2, forKey: "pt_tone_cursor_pretest")
        let upgraded = ToneTrainingViewModel(sequencer: ToneSequencer(), recorder: FakeRecorder())
        upgraded.loadCurrent()
        XCTAssertEqual(upgraded.mode, .practice)
        XCTAssertNotNil(upgraded.currentLexeme)
        XCTAssertEqual(upgraded.currentLexeme?.id, ToneSequencer().pool.first?.id,
                       "应从普通练习的词表开始，而不是续上旧的前测位置")
    }

    func testAnyWordCanBeSelectedAndNextWrapsAround() {
        let sequencer = ToneSequencer()
        let pool = sequencer.pool
        XCTAssertGreaterThan(pool.count, 4)
        XCTAssertTrue(sequencer.select(lexemeID: pool.last!.id))
        XCTAssertEqual(sequencer.currentLexeme?.id, pool.last?.id)
        XCTAssertEqual(sequencer.progress.index, pool.count)
        sequencer.advance()
        XCTAssertEqual(sequencer.currentLexeme?.id, pool.first?.id, "到末尾回到开头，没有「完成」死路")
        XCTAssertFalse(sequencer.select(lexemeID: "no-such-word"))
        XCTAssertEqual(sequencer.currentLexeme?.id, pool.first?.id)
    }

    // MARK: - 状态机与有效结果（U03 / A14）

    func testRecordingProducesFeedbackAndStatesAdvanceInOrder() async {
        XCTAssertEqual(vm.stage, .ready)
        vm.startRecording()
        XCTAssertEqual(vm.stage, .recording)
        XCTAssertTrue(vm.isBusy)
        recorder.speak(tones: vm.currentLexeme!.tones)
        await settle()
        vm.stopRecordingAndEvaluate()

        XCTAssertEqual(vm.stage, .feedback)
        let result = try? XCTUnwrap(vm.feedbackResult)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.dtwScore.isFinite ?? false)
        XCTAssertFalse(vm.studentF0.isEmpty, "有效录音应有可画的曲线")
        XCTAssertFalse(vm.isBusy)
        XCTAssertTrue(LearnerRecordingStore.shared.hasRecording, "录音应可回听")
    }

    /// 「结果已显示」由界面在结果真正出现时报告；重绘多少次都只算一次（A09）
    func testResultDisplayedIsReportedOncePerAttempt() async {
        await record()
        XCTAssertTrue(attempts.isEmpty, "结果还没呈现，尝试还没结账")
        XCTAssertTrue(events(.feedbackDisplayed).isEmpty)

        vm.feedbackDidAppear()
        vm.feedbackDidAppear()            // 视图重绘
        vm.feedbackDidAppear()

        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.status, .succeeded)
        XCTAssertNotNil(attempts.first?.resultDisplayedAt)
        XCTAssertEqual(attempts.first?.taskType, .fixedWord)
        XCTAssertEqual(events(.feedbackDisplayed).count, 1)
        XCTAssertEqual(events(.feedbackDisplayed).first?.attemptID, vm.currentAttemptID)
        XCTAssertEqual(SurveyCenter.qualifyingCount, 1)
    }

    /// 没通过的有效结果照样是一次合格练习（A08：低分仍计次）
    func testLowScoringButValidResultStillCounts() async throws {
        await record(matching: false)
        let result = try XCTUnwrap(vm.feedbackResult)
        try XCTSkipIf(result.grade != .fail, "这一词念错调后仍被判通过，无法用它验证低分路径")
        vm.feedbackDidAppear()
        XCTAssertEqual(attempts.first?.passed, false)
        XCTAssertEqual(attempts.first?.status, .succeeded, "低分是有效结果，不是失败状态")
        XCTAssertEqual(SurveyCenter.qualifyingCount, 1)
    }

    /// 每次真实录音一个新编号；重录关联上一次；换词后不再关联
    func testEachRecordingGetsANewAttemptIDAndRetriesAreLinked() async {
        await record()
        let first = vm.currentAttemptID
        vm.feedbackDidAppear()
        await record()
        let second = vm.currentAttemptID
        vm.feedbackDidAppear()

        XCTAssertNotNil(first)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertNil(attempts.first { $0.attemptID == first }?.retryOfAttemptID)
        XCTAssertEqual(attempts.first { $0.attemptID == second }?.retryOfAttemptID, first)

        vm.loadNext()
        await record()
        vm.feedbackDidAppear()
        XCTAssertNil(attempts.first { $0.attemptID == vm.currentAttemptID }?.retryOfAttemptID,
                     "换了词就不是上一词的重录")
    }

    // MARK: - 技术失败（A14）

    /// 没录到声音：可恢复的失败，**不是低分**，没有成绩，不算练过这个词
    func testSilentRecordingIsATechnicalFailureNotALowScore() async {
        let word = vm.currentLexeme!.id
        vm.startRecording()
        recorder.silence()
        await settle()
        vm.stopRecordingAndEvaluate()

        XCTAssertEqual(vm.stage, .failed(.noVoice))
        XCTAssertNil(vm.feedbackResult, "技术失败不得出现任何结果")
        XCTAssertTrue(vm.canRecord, "可以直接重录")
        let attempt = attempts.first
        XCTAssertEqual(attempt?.status, .analysisFailed)
        XCTAssertEqual(attempt?.errorCode, .noSignal)
        XCTAssertNil(attempt?.metricValue, "没有成绩，不是零分")
        XCTAssertNil(attempt?.passed)
        XCTAssertNil(attempt?.resultDisplayedAt)
        XCTAssertEqual(ToneAttemptStore.attempts(for: word), 0, "没录上不算练过")
        vm.feedbackDidAppear()
        XCTAssertEqual(SurveyCenter.qualifyingCount, 0, "技术失败不计入合格练习")
        XCTAssertTrue(events(.feedbackDisplayed).isEmpty)
    }

    /// 录音起不来：给出可执行的提示，不是一个按了没反应的按钮
    func testRecorderStartFailureIsSurfacedAndRecorded() {
        recorder.startError = AudioEngine.AudioEngineError.invalidInputFormat
        vm.startRecording()
        XCTAssertEqual(vm.stage, .failed(.microphoneUnavailable))
        XCTAssertEqual(attempts.first?.status, .recordingFailed)
        XCTAssertNotNil(attempts.first?.errorCode)
        XCTAssertNil(attempts.first?.metricValue)

        recorder.startError = nil
        vm.startRecording()
        XCTAssertEqual(vm.stage, .recording, "失败后可以直接再试")
    }

    // MARK: - 取消与被打断（A18）

    func testLeavingThePageWhileRecordingCancelsWithoutAResult() async {
        vm.startRecording()
        recorder.speak(tones: vm.currentLexeme!.tones)
        await settle()
        vm.leavePage()

        XCTAssertFalse(recorder.isRunning, "离开页面后不得继续录音")
        XCTAssertNil(vm.feedbackResult)
        XCTAssertEqual(attempts.first?.status, .cancelled)
        XCTAssertNil(attempts.first?.metricValue)
        XCTAssertFalse(LearnerRecordingStore.shared.hasRecording)
    }

    func testInterruptionStopsRecordingAndIsRecordedAsUnknownInterruption() async {
        vm.startRecording()
        recorder.speak(tones: vm.currentLexeme!.tones)
        await settle()
        vm.handleInterruption()

        XCTAssertFalse(recorder.isRunning, "被打断后不得在后台继续录音")
        XCTAssertEqual(vm.stage, .failed(.interrupted))
        XCTAssertNil(vm.feedbackResult)
        XCTAssertEqual(attempts.first?.status, .interruptedUnknown)
        XCTAssertNil(attempts.first?.metricValue)
        XCTAssertTrue(vm.canRecord)
    }

    func testInterruptionWhenNotRecordingDoesNothing() {
        vm.handleInterruption()
        XCTAssertEqual(vm.stage, .ready)
        XCTAssertTrue(attempts.isEmpty)
    }

    // MARK: - 录音中不能切词

    func testCannotSwitchWordOrStartSelfTestWhileRecording() {
        let word = vm.currentLexeme?.id
        vm.startRecording()
        vm.loadNext()
        vm.select(lexemeID: ToneSequencer().pool.last!.id)
        vm.beginSelfTest()
        XCTAssertEqual(vm.currentLexeme?.id, word)
        XCTAssertEqual(vm.mode, .practice)
        XCTAssertEqual(vm.stage, .recording)
        vm.cancelRecording()
    }

    func testPressingRecordTwiceDoesNotStartTwoRecordings() {
        vm.startRecording()
        vm.startRecording()
        XCTAssertEqual(recorder.startCount, 1, "重复点击不得重复启动录音")
        vm.cancelRecording()
    }

    // MARK: - 使用后问卷的邀请时机（A08）

    /// 第 5 次结果呈现后，邀请要等用户结束这次反馈（换词 / 再试）才出现
    func testPostSurveyInvitationWaitsUntilTheLearnerLeavesTheFeedback() async {
        for _ in 0..<5 {
            await record()
            vm.feedbackDidAppear()
        }
        XCTAssertEqual(SurveyCenter.qualifyingCount, 5)
        XCTAssertNil(vm.postSurveyInvitation, "还在看第 5 次的反馈，不能弹问卷")
        XCTAssertNil(SurveyCenter.record(SurveyCenter.postKey))

        vm.clearFeedbackForRetry()
        XCTAssertNotNil(vm.postSurveyInvitation)
        XCTAssertEqual(SurveyCenter.record(SurveyCenter.postKey)?.status, .invited)
        XCTAssertEqual(SurveyCenter.record(SurveyCenter.postKey)?.qualifyingAttemptsAtInvite, 5)
    }

    /// 开始下一次录音不触发邀请——不能在用户正要录音时弹东西
    func testStartingAnotherRecordingDoesNotPopTheInvitation() async {
        for _ in 0..<5 {
            await record()
            vm.feedbackDidAppear()
        }
        vm.startRecording()
        XCTAssertNil(vm.postSurveyInvitation)
        vm.cancelRecording()
    }

    // MARK: - 自测（R06 / U04 / A17）

    func testSelfTestShowsNoEvaluationAndDoesNotCountTowardTheSurvey() async {
        let practiceWord = vm.currentLexeme?.id
        vm.beginSelfTest()
        XCTAssertEqual(vm.mode, .selfTest)
        let total = vm.selfTest?.total ?? 0
        XCTAssertGreaterThan(total, 0)
        XCTAssertEqual(vm.selfTest?.position, 1)
        XCTAssertFalse(vm.canReplay, "自测不提供回听")

        vm.startRecording()
        recorder.speak(tones: vm.currentLexeme!.tones)
        await settle()
        vm.stopRecordingAndEvaluate()

        XCTAssertEqual(vm.stage, .selfTestRecorded)
        XCTAssertNil(vm.feedbackResult, "自测不得呈现结果")
        XCTAssertTrue(vm.studentF0.isEmpty, "自测不得画曲线")
        let attempt = attempts.first
        XCTAssertEqual(attempt?.taskType, .selfTest)
        XCTAssertEqual(attempt?.status, .succeeded)
        XCTAssertNil(attempt?.resultDisplayedAt, "自测没有呈现结果，不得填结果显示时间")
        XCTAssertNotNil(attempt?.priorPracticeCount)
        vm.feedbackDidAppear()
        XCTAssertEqual(SurveyCenter.qualifyingCount, 0, "自测不计入使用后问卷的次数")
        XCTAssertTrue(events(.feedbackDisplayed).isEmpty)
        XCTAssertFalse(LearnerRecordingStore.shared.hasRecording)

        // 示范、建议在自测里不可用
        vm.playSample()
        XCTAssertNil(vm.playing)
        vm.openAdvice()
        XCTAssertFalse(vm.showAdvice)

        vm.endSelfTest()                         // 随时可以退出
        XCTAssertEqual(vm.mode, .practice)
        XCTAssertNil(vm.selfTest)
        XCTAssertEqual(vm.currentLexeme?.id, practiceWord, "回到原来在练的词")
        XCTAssertEqual(vm.stage, .ready, "普通练习可以继续，没有被锁住")
    }

    /// 自测里的技术失败可以重录，不算完成这一题
    func testSelfTestTechnicalFailureDoesNotAdvance() async {
        vm.beginSelfTest()
        let word = vm.currentLexeme?.id
        vm.startRecording()
        recorder.silence()
        await settle()
        vm.stopRecordingAndEvaluate()

        XCTAssertEqual(vm.stage, .failed(.noVoice))
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertEqual(vm.currentLexeme?.id, word, "没录上不能自动跳到下一题")
        XCTAssertEqual(vm.selfTest?.position, 1)
        XCTAssertNil(attempts.first?.metricValue)
        XCTAssertTrue(vm.canRecord)
    }

    /// 走完全部词：只陈述完成，返回后普通练习照常
    func testSelfTestCompletionReturnsToPractice() async {
        vm.beginSelfTest()
        let total = vm.selfTest?.total ?? 0
        for _ in 0..<total {
            vm.startRecording()
            recorder.speak(tones: vm.currentLexeme!.tones)
            await settle()
            vm.stopRecordingAndEvaluate()
            try? await Task.sleep(nanoseconds: 900_000_000)      // 等自动进入下一词
        }
        XCTAssertTrue(vm.selfTestFinished)
        XCTAssertEqual(attempts.filter { $0.taskType == .selfTest }.count, total)

        vm.endSelfTest()
        XCTAssertEqual(vm.mode, .practice)
        XCTAssertFalse(vm.selfTestFinished)
        XCTAssertNotNil(vm.currentLexeme)
        vm.startRecording()
        XCTAssertEqual(vm.stage, .recording, "自测结束后普通练习可继续，没有永久完成的死路")
        vm.cancelRecording()
    }

    func testCancellingSelfTestWhileRecordingRecordsACancelledAttempt() async {
        vm.beginSelfTest()
        vm.startRecording()
        recorder.speak(tones: vm.currentLexeme!.tones)
        await settle()
        vm.endSelfTest()
        XCTAssertFalse(recorder.isRunning)
        XCTAssertEqual(attempts.first?.status, .cancelled)
        XCTAssertEqual(attempts.first?.taskType, .selfTest)
        XCTAssertEqual(vm.mode, .practice)
    }

    func testSelfTestSessionProgress() {
        var session = SelfTestSession(words: ["a", "b"])
        XCTAssertEqual(session.position, 1)
        XCTAssertEqual(session.currentID, "a")
        session.completeCurrent()
        XCTAssertEqual(session.position, 2)
        XCTAssertFalse(session.isFinished)
        session.completeCurrent()
        XCTAssertTrue(session.isFinished)
        XCTAssertNil(session.currentID)
        session.completeCurrent()
        XCTAssertEqual(session.total, 2)
    }

    // MARK: - 未参加研究的人照常练习，不产生研究记录（A05）

    func testNonParticipantPractisesNormallyWithoutResearchRecords() async {
        ResearchTestSupport.freshAccount()
        await record()
        vm.feedbackDidAppear()
        XCTAssertEqual(vm.stage, .feedback, "普通使用不降级")
        XCTAssertNotNil(vm.feedbackResult)
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty)
        XCTAssertEqual(SurveyCenter.qualifyingCount, 0)
    }
}
