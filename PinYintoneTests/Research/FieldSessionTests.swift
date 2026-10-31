import XCTest
@testable import PinYintone

/// 现场实测（2026-10-28）：前测 → 训练 → 后测、裸测不给评价、录音只在同意后才留、
/// 不限国籍、换新一轮研究时旧状态不挡邀请。
@MainActor
final class FieldSessionTests: XCTestCase {

    private var recorder: FakeRecorder!
    private var vm: ToneTrainingViewModel!
    private var savedDefaults: [String: Any?] = [:]
    private let touchedKeys = ["pt_tone_attempts", "pt_tone_practice_cursor"]

    /// 一个测试词、一个训练词、每个训练词 2 次有效结果：走完全程只要几秒
    private let small = FieldProtocol(protocolVersion: "field-test", testWords: ["hanzi"],
                                      trainingWords: ["xianzai"], trainingValidAttemptsPerWord: 2)

    override func setUp() {
        super.setUp()
        for key in touchedKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        StubURLProtocol.install()
        ResearchTestSupport.enrolledAccount()
        makeViewModel()
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

    private func makeViewModel() {
        recorder = FakeRecorder()
        vm = ToneTrainingViewModel(sequencer: ToneSequencer(), recorder: recorder)
        vm.loadCurrent()
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func record() async {
        vm.startRecording()
        recorder.speak(tones: vm.currentLexeme?.tones ?? [1])
        await settle()
        vm.stopRecordingAndEvaluate()
    }

    /// 裸测录完后等它自动进下一词
    private func waitForAdvance() async {
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    private var attempts: [ResearchAttemptRecord] { ResearchAttemptLog.shared.pending }
    private func events(_ name: ResearchEventName) -> [ResearchEvent] {
        ResearchEventLog.shared.pending.filter { $0.name == name }
    }

    // MARK: - 完整流程

    func testFullSessionRecordsPretestTrainingAndPosttest() async {
        XCTAssertTrue(vm.beginFieldSession(small))
        XCTAssertEqual(vm.mode, .field)
        XCTAssertNil(vm.currentLexeme, "先显示说明页")
        XCTAssertFalse(vm.canRecord, "说明页上不能录音")

        // 前测：裸测
        vm.continueFieldSession()
        XCTAssertEqual(vm.currentLexeme?.id, "hanzi")
        XCTAssertTrue(vm.isBareTest)
        XCTAssertFalse(vm.showsFeedback)
        await record()
        XCTAssertEqual(vm.stage, .selfTestRecorded)
        XCTAssertNil(vm.feedbackResult, "前测不得呈现结果")
        XCTAssertTrue(vm.studentF0.isEmpty, "前测不得画曲线")
        vm.playSample()
        XCTAssertNil(vm.playing, "前测没有示范")
        await waitForAdvance()
        XCTAssertEqual(vm.field?.stepFinished, true)
        XCTAssertNil(vm.currentLexeme, "段落之间停下来，等学习者点继续")

        // 训练：有反馈，练够次数才能换词
        vm.continueFieldSession()
        XCTAssertEqual(vm.currentLexeme?.id, "xianzai")
        XCTAssertTrue(vm.showsFeedback)
        await record()
        XCTAssertEqual(vm.stage, .feedback)
        XCTAssertNotNil(vm.feedbackResult)
        vm.feedbackDidAppear()
        XCTAssertFalse(vm.fieldTrainingWordDone)
        vm.nextFieldTrainingWord()
        XCTAssertEqual(vm.currentLexeme?.id, "xianzai", "没练够不能跳过")
        vm.clearFeedbackForRetry()
        await record()
        vm.feedbackDidAppear()
        XCTAssertTrue(vm.fieldTrainingWordDone)
        vm.nextFieldTrainingWord()
        XCTAssertEqual(vm.field?.stepFinished, true)

        // 后测：同一组测试词，裸测
        vm.continueFieldSession()
        XCTAssertEqual(vm.field?.step, .posttest)
        XCTAssertEqual(vm.currentLexeme?.id, "hanzi", "后测与前测是同一组词")
        await record()
        XCTAssertNil(vm.feedbackResult)
        await waitForAdvance()
        XCTAssertEqual(vm.field?.isComplete, true)

        // 研究记录
        let fieldID = vm.field?.id
        XCTAssertEqual(attempts.map(\.taskType), [.pretest, .fixedWord, .fixedWord, .posttest])
        XCTAssertTrue(attempts.allSatisfy { $0.fieldSessionID == fieldID && fieldID != nil })
        for a in attempts where a.taskType.isBareTest {
            XCTAssertNil(a.resultDisplayedAt, "裸测没有呈现结果，不得填结果显示时间")
            XCTAssertNotNil(a.priorPracticeCount)
        }
        XCTAssertEqual(attempts.filter { $0.taskType == .fixedWord }
                        .compactMap(\.resultDisplayedAt).count, 2)
        XCTAssertEqual(events(.fieldSessionStarted).count, 1)
        XCTAssertEqual(events(.fieldStepCompleted).map { $0.payload["step"] },
                       ["pretest", "training", "posttest"])

        vm.endFieldSession()
        XCTAssertEqual(events(.fieldSessionEnded).first?.payload["outcome"], "completed")
        XCTAssertEqual(vm.mode, .practice)
        XCTAssertNil(vm.field)
        XCTAssertNotNil(vm.currentLexeme, "回到普通练习，没有被锁住")
    }

    func testLeavingHalfwayIsRecordedAsAbandonedAndUnlocksPractice() async {
        vm.beginFieldSession(small)
        vm.continueFieldSession()
        vm.startRecording()
        recorder.speak(tones: vm.currentLexeme!.tones)
        await settle()
        vm.endFieldSession()

        XCTAssertFalse(recorder.isRunning)
        XCTAssertEqual(attempts.first?.status, .cancelled)
        XCTAssertEqual(attempts.first?.taskType, .pretest)
        let ended = events(.fieldSessionEnded).first
        XCTAssertEqual(ended?.payload["outcome"], "abandoned")
        XCTAssertEqual(ended?.payload["last_step"], "pretest")
        XCTAssertEqual(vm.mode, .practice)
        XCTAssertEqual(vm.stage, .ready)
    }

    func testPretestTechnicalFailureDoesNotAdvance() async {
        vm.beginFieldSession(small)
        vm.continueFieldSession()
        vm.startRecording()
        recorder.silence()
        await settle()
        vm.stopRecordingAndEvaluate()
        await waitForAdvance()
        XCTAssertEqual(vm.stage, .failed(.noVoice))
        XCTAssertEqual(vm.currentLexeme?.id, "hanzi", "没录上不算完成这一题")
        XCTAssertEqual(vm.field?.step, .pretest)
    }

    func testNonParticipantCanRunTheFlowButLeavesNoResearchRecords() async {
        ResearchTestSupport.freshAccount()          // 没参加研究
        makeViewModel()
        vm.beginFieldSession(small)
        vm.continueFieldSession()
        await record()
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty)
    }

    // MARK: - 录音

    private func waitForRecordings(_ count: Int) async {
        for _ in 0..<60 where ResearchRecordingQueue.shared.pending.count < count {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testFieldRecordingsQueuedWhenConsentIncludesAudio() async {
        ResearchTestSupport.enrolledAccount(consentVersion: "consent-2.0", audioUpload: true)
        makeViewModel()
        vm.beginFieldSession(small)
        vm.continueFieldSession()
        await record()
        await waitForRecordings(1)
        let item = ResearchRecordingQueue.shared.pending.first
        XCTAssertEqual(item?.attemptID, attempts.first?.attemptID)
        XCTAssertGreaterThan(item?.byteSize ?? 0, 0)
        XCTAssertEqual(item?.sha256.count, 64)
        XCTAssertNotNil(item.flatMap { ResearchRecordingQueue.shared.data(for: $0) })

        // 退出研究：本机录音全部删除
        ResearchEnrollment.withdraw()
        XCTAssertTrue(ResearchRecordingQueue.shared.pending.isEmpty)
        XCTAssertNil(item.flatMap { ResearchRecordingQueue.shared.data(for: $0) })
    }

    func testNoRecordingKeptWithoutAudioConsent() async {
        // 同意的是不含录音的 1.1：即使配置收录音也不留
        ResearchTestSupport.enrolledAccount(consentVersion: "consent-1.1", audioUpload: true)
        makeViewModel()
        vm.beginFieldSession(small)
        vm.continueFieldSession()
        await record()
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(ResearchRecordingQueue.shared.pending.isEmpty)
    }

    func testOrdinaryPracticeNeverKeepsRecordings() async {
        ResearchTestSupport.enrolledAccount(consentVersion: "consent-2.0", audioUpload: true)
        makeViewModel()
        await record()                              // 普通练习
        vm.feedbackDidAppear()                      // 结果显示后这次尝试才结账
        vm.beginSelfTest()
        await record()                              // 自测
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertTrue(ResearchRecordingQueue.shared.pending.isEmpty,
                      "普通练习与自测的录音从不上传")
    }

    func testCancelledFieldAttemptKeepsNoRecording() async {
        ResearchTestSupport.enrolledAccount(consentVersion: "consent-2.0", audioUpload: true)
        makeViewModel()
        vm.beginFieldSession(small)
        vm.continueFieldSession()
        vm.startRecording()
        recorder.speak(tones: vm.currentLexeme!.tones)
        await settle()
        vm.cancelRecording()
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(ResearchRecordingQueue.shared.pending.isEmpty)
    }

    func testAACEncodingProducesACompactADTSStream() throws {
        let pcm = (0..<16_000).map { Int16(sin(Double($0) * 0.05) * 8000) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).aac")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try ResearchRecordingQueue.encodeAAC(pcm: pcm, to: url)
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertLessThan(data.count, 32_000, "1 秒约 4 KB，远小于原始 PCM 的 32 KB")
        // ADTS 帧头的同步字 0xFFF；不是 m4a（那样文件头会多出约 24 KB 空白）
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1] & 0xF0, 0xF0)
    }

    // MARK: - 协议与入口

    func testShippedProtocolIsConsistentAndMatchesItself() throws {
        let p = try XCTUnwrap(FieldProtocol.bundled)
        XCTAssertTrue(Set(p.testWords).isDisjoint(with: p.trainingWords), "测试词与训练词不得重叠")
        for id in p.testWords + p.trainingWords {
            XCTAssertNotNil(CorpusLoader.shared.lexeme(id: id), id)
            XCTAssertNotNil(ResearchLexicon.versionID(for: id), id)
        }
        let spec = ResearchTestSupport.fieldProtocolSpec(p)
        XCTAssertTrue(p.matches(spec, version: p.protocolVersion))
        XCTAssertFalse(p.matches(spec, version: "field-0.9"), "版本不同就不是同一份协议")
        let swapped = APIClient.FieldProtocolSpec(
            lexiconVersion: spec.lexiconVersion, testLexemeVersionIDs: spec.trainingLexemeVersionIDs,
            trainingLexemeVersionIDs: spec.testLexemeVersionIDs,
            trainingValidAttemptsPerWord: spec.trainingValidAttemptsPerWord)
        XCTAssertFalse(p.matches(swapped, version: p.protocolVersion))
    }

    func testFieldSessionOnlyOfferedToEnrolledParticipantsOfTheCurrentManifest() {
        ResearchTestSupport.openManifest(withFieldProtocol: false)
        XCTAssertFalse(ResearchConfig.shared.fieldSessionAvailable(), "配置没带协议")
        ResearchTestSupport.openManifest(withFieldProtocol: true)
        XCTAssertTrue(ResearchConfig.shared.fieldSessionAvailable())
        ResearchTestSupport.freshAccount()
        ResearchTestSupport.openManifest(withFieldProtocol: true)
        XCTAssertFalse(ResearchConfig.shared.fieldSessionAvailable(), "没参加研究的人看不到入口")
    }

    func testFieldSessionStateMachine() {
        var s = FieldSession(protocol: FieldProtocol(protocolVersion: "v", testWords: ["a", "b"],
                                                     trainingWords: ["c"],
                                                     trainingValidAttemptsPerWord: 2))
        XCTAssertNil(s.currentID, "开始之前没有词")
        s.start()
        XCTAssertEqual(s.currentID, "a")
        s.recordTrainingResult()                     // 前测里不计训练次数
        s.completeTestWord()
        XCTAssertEqual(s.currentID, "b")
        s.completeTestWord()
        XCTAssertTrue(s.stepFinished)
        XCTAssertNil(s.currentID)
        s.beginNextStep()
        XCTAssertEqual(s.step, .training)
        XCTAssertEqual(s.currentID, "c")
        s.completeTestWord()                         // 训练段不能当测试推进
        XCTAssertEqual(s.currentID, "c")
        XCTAssertFalse(s.recordTrainingResult())
        s.nextTrainingWord()
        XCTAssertEqual(s.currentID, "c", "没练够不能换词")
        XCTAssertTrue(s.recordTrainingResult())
        s.nextTrainingWord()
        XCTAssertTrue(s.stepFinished)
        s.beginNextStep()
        XCTAssertEqual(s.step, .posttest)
        XCTAssertEqual(s.words, ["a", "b"])
        s.completeTestWord(); s.completeTestWord()
        XCTAssertTrue(s.isComplete)
    }

    // MARK: - 纳入与新一轮

    func testAnyNationalityIsEligibleThisRound() {
        let ok = ResearchEligibility.evaluate(
            background: ResearchTestSupport.background(nationality: ["other"]), consentGranted: true)
        XCTAssertEqual(ok, .eligible)
        let skipped = ResearchEligibility.evaluate(
            background: ResearchTestSupport.background(nationality: nil), consentGranted: true)
        XCTAssertEqual(skipped, .eligible, "国籍不参与判定，没答也不挡")
        let minor = ResearchEligibility.evaluate(
            background: ResearchTestSupport.background(adult: "minor", nationality: ["other"]),
            consentGranted: true)
        XCTAssertEqual(minor, .excluded(.age))
        XCTAssertEqual(ResearchEligibility.version, "eligibility-3.0")
    }

    func testNewStudyRoundReopensTheInvitationOnceOldDataIsSent() {
        ResearchTestSupport.enrolledAccount()       // 第一轮（study-test）已参与，队列为空
        ResearchStore.shared.rollOverToNewStudyIfNeeded("study-test")
        XCTAssertEqual(ResearchStore.shared.state.participation, .enrolled, "同一轮不动")

        ResearchStore.shared.rollOverToNewStudyIfNeeded("study-round-2")
        XCTAssertEqual(ResearchStore.shared.state.participation, .notAsked)
        XCTAssertNil(ResearchStore.shared.state.participantID)
    }

    func testNewStudyRoundWaitsForUnsentData() {
        ResearchTestSupport.enrolledAccount()
        ResearchAttemptLog.shared.begin(attemptID: UUID(), taskType: .fixedWord,
                                        lexemeVersionID: "v", priorPracticeCount: nil)
        let id = UUID()
        ResearchAttemptLog.shared.begin(attemptID: id, taskType: .fixedWord,
                                        lexemeVersionID: "v", priorPracticeCount: nil)
        ResearchAttemptLog.shared.markCancelled(id)
        ResearchStore.shared.rollOverToNewStudyIfNeeded("study-round-2")
        XCTAssertEqual(ResearchStore.shared.state.participation, .enrolled,
                       "上一轮还有没传完的记录，先按旧身份传完")
    }

    func testWithdrawnInFirstRoundCanJoinTheNextRound() {
        ResearchTestSupport.freshAccount()
        ResearchStore.shared.update { $0.participation = .withdrawn }   // 升级前留下的，没有轮次
        ResearchStore.shared.rollOverToNewStudyIfNeeded("study-round-2")
        XCTAssertEqual(ResearchStore.shared.state.participation, .notAsked)
    }

    /// 本轮明确拒绝的人：刷新配置时不能被当成「上一轮」翻篇、邀请又冒出来
    func testDeclineInThisRoundSticks() {
        ResearchTestSupport.freshAccount()
        ResearchTestSupport.openManifest()
        ResearchConsent.decline()
        ResearchStore.shared.rollOverToNewStudyIfNeeded("study-test")
        XCTAssertEqual(ResearchStore.shared.state.participation, .declined)
    }

    // MARK: - 登录后的知情同意

    func testSignupConsentWaitsForAnOpenStudyAndPopsOnce() {
        ResearchTestSupport.freshAccount()
        ResearchStore.shared.update { $0.signupConsentDue = true }
        ResearchConfig.shared.setAvailableForTesting(nil)
        XCTAssertFalse(ResearchEnrollment.consumeSignupConsent(), "没有开放的研究不弹")
        XCTAssertTrue(ResearchStore.shared.state.signupConsentDue, "开放后再弹")
        ResearchTestSupport.openManifest()
        XCTAssertTrue(ResearchEnrollment.consumeSignupConsent())
        XCTAssertFalse(ResearchEnrollment.consumeSignupConsent(), "只弹一次")
        XCTAssertEqual(ResearchStore.shared.state.participation, .notAsked,
                       "弹出不等于同意：不打勾同意就不产生任何研究数据")
        XCTAssertFalse(ResearchGate.shouldCollect())
    }

    func testSignupConsentNotShownToSomeoneWhoAlreadyAnswered() {
        ResearchTestSupport.freshAccount()
        ResearchTestSupport.openManifest()
        ResearchConsent.decline()
        ResearchStore.shared.update { $0.signupConsentDue = true }
        XCTAssertFalse(ResearchEnrollment.consumeSignupConsent())
    }

    func testBothConsentTextsListTheWeChatBenefit() {
        for text in ResearchConsent.Text.allCases {
            XCTAssertTrue(text.sections.contains { $0.body == "consent_benefit_body" })
        }
        XCTAssertEqual(ResearchConsent.wechatID, "herecomes_zhuozhuo")
    }

    func testSpanishAndItalianGlosses() throws {
        let word = try XCTUnwrap(CorpusLoader.shared.lexeme(id: "yisheng"))
        XCTAssertEqual(word.glosses(for: "es").primary, "Médico")
        XCTAssertEqual(word.glosses(for: "it").primary, "Medico")
        XCTAssertEqual(word.glosses(for: "fr").primary, "Médecin")
        XCTAssertNotNil(word.glosses(for: "fr").secondary)
    }

    /// 语言背景题与注册页都能选西班牙语、意大利语
    func testSpanishAndItalianCanBeChosenAsLanguages() throws {
        let form = try XCTUnwrap(SurveyFormLoader.bundled[SurveyCenter.backgroundKey])
        XCTAssertEqual(form.formVersion, "background_v1-1.2", "选项变了版本号必须跟着变")
        for id in ["B04", "B05"] {
            let q = try XCTUnwrap(form.questions.first { $0.questionId == id })
            let codes = q.options.map(\.code)
            XCTAssertTrue(codes.contains("spanish") && codes.contains("italian"), id)
            XCTAssertEqual(codes.last, "prefer_not", "互斥项仍排最后")
        }
        XCTAssertTrue(SpokenLanguage.displayOrder.contains(.spanish))
        XCTAssertTrue(SpokenLanguage.displayOrder.contains(.italian))
        XCTAssertEqual(Set(SpokenLanguage.displayOrder), Set(SpokenLanguage.allCases))
    }
}
