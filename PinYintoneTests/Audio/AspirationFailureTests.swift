import XCTest
@testable import PinYintone

/// 送气练习（关卡 1）的技术失败处理。
///
/// 关卡 2、3 都修过同类问题，关卡 1 一直没查：
/// - 录音起不来只设 isRecording = false，**无任何提示**（禁令 11）
/// - 没录上时照样落一条 triggerRate = 0 / passed = false 的记录——
///   等于把麦克风故障算成「送气没做到」（禁令 9）
@MainActor
final class AspirationFailureTests: XCTestCase {

    private func make() -> (AspirationViewModel, FakeRecorder) {
        let recorder = FakeRecorder()
        let vm = AspirationViewModel(recorder: recorder)
        return (vm, recorder)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    /// 选到指定类型的词
    private func load(_ vm: AspirationViewModel, aspirated: Bool) {
        for _ in 0..<12 {
            vm.loadNextLexeme()
            if vm.currentLexeme?.aspirationTarget?.aspirated == aspirated { return }
        }
        XCTFail("语料里没有这类词")
    }

    /// 校准 500ms → 出声 `seconds` 秒 → 点停止
    private func run(_ vm: AspirationViewModel, _ recorder: FakeRecorder, seconds: Double) async {
        vm.toggleRecording()
        recorder.silence(seconds: 0.5)
        await settle()
        XCTAssertEqual(vm.stage, .recording)
        if seconds > 0 { recorder.speak(tones: [1], seconds: seconds) }
        recorder.silence(seconds: 0.2)
        await settle()
        vm.toggleRecording()
    }

    func testOpeningThePageDoesNotStartTheMicrophone() {
        let (vm, recorder) = make()
        vm.loadNextLexeme()
        XCTAssertEqual(vm.stage, .idle)
        XCTAssertEqual(recorder.startCount, 0, "换词、进页面都不开麦，点了开始才录")
    }

    /// 词集区分：3 个送气 + 3 个不送气，声母与词的第一个字拼音一致
    func testCorpusMarksAspiratedAndUnaspiratedWords() throws {
        let words = CorpusLoader.shared.lexemes(in: .aspiration)
        let targets = try words.map { try XCTUnwrap($0.aspirationTarget, $0.id) }
        XCTAssertEqual(Set(targets.filter(\.aspirated).map(\.initial)), ["p", "t", "k"])
        XCTAssertEqual(Set(targets.filter { !$0.aspirated }.map(\.initial)), ["b", "d", "g"])
        for w in words {
            XCTAssertTrue(w.pinyin.hasPrefix(w.aspirationTarget!.initial), w.id)
        }
    }

    func testAspiratedNeedsABurst() async {
        let (vm, recorder) = make()
        load(vm, aspirated: true)
        await run(vm, recorder, seconds: 0.9)
        XCTAssertEqual(vm.passed, true)
        XCTAssertFalse(recorder.isRunning, "点停止后麦克风关闭")

        // 太短的一声够不到 60%：第一帧不能算 100%（分母固定 6 帧）
        await run(vm, recorder, seconds: 0.3)
        XCTAssertEqual(vm.passed, false)
        XCTAssertEqual(vm.peakRate, 0.5, accuracy: 0.01)
    }

    func testUnaspiratedMustNotBurst() async {
        let (vm, recorder) = make()
        load(vm, aspirated: false)
        await run(vm, recorder, seconds: 0.3)
        XCTAssertEqual(vm.passed, true, "没有爆破：不送气音就该这样")
        await run(vm, recorder, seconds: 0.9)
        XCTAssertEqual(vm.passed, false, "气流太强：不送气音不通过")
    }

    /// 没出声是技术失败：有提示、没成绩，不能算成「不送气做对了」（禁令 9）
    func testSilenceIsATechnicalFailureForBothKinds() async {
        for aspirated in [true, false] {
            let (vm, recorder) = make()
            load(vm, aspirated: aspirated)
            await run(vm, recorder, seconds: 0)
            XCTAssertNil(vm.passed)
            XCTAssertEqual(vm.stage, .idle)
            XCTAssertNotNil(vm.retryHint)
        }
    }

    func testStoppingDuringCalibrationIsNotAResult() {
        let (vm, recorder) = make()
        vm.loadNextLexeme()
        vm.toggleRecording()
        XCTAssertEqual(vm.stage, .calibrating)
        vm.toggleRecording()
        XCTAssertFalse(recorder.isRunning)
        XCTAssertNil(vm.passed)
        XCTAssertNotNil(vm.retryHint)
    }

    func testMicrophoneStartFailureGivesAHint() {
        let (vm, recorder) = make()
        vm.loadNextLexeme()
        recorder.startError = AudioEngine.AudioEngineError.invalidInputFormat
        vm.toggleRecording()
        XCTAssertEqual(vm.stage, .idle)
        XCTAssertNotNil(vm.retryHint, "禁令 11：录音起不来必须说出来")
    }

    func testLeavingWhileRecordingStopsWithoutAResult() async {
        let (vm, recorder) = make()
        vm.loadNextLexeme()
        vm.toggleRecording()
        recorder.silence(seconds: 0.5)
        await settle()
        recorder.speak(tones: [1], seconds: 0.9)
        await settle()
        vm.leavePage()
        XCTAssertFalse(recorder.isRunning)
        XCTAssertNil(vm.passed)
    }

    func testRuleDirectionsAndThresholdBoundary() {
        XCTAssertTrue(AspirationRule.passes(aspirated: true, peakRate: 0.6))
        XCTAssertFalse(AspirationRule.passes(aspirated: true, peakRate: 0.59))
        XCTAssertFalse(AspirationRule.passes(aspirated: false, peakRate: 0.6))
        XCTAssertTrue(AspirationRule.passes(aspirated: false, peakRate: 0.59))
    }

    /// 提示文案四语齐备
    func testRetryCopyLocalized() throws {
        for lang in ["zh-Hans", "en", "fr", "ar"] {
            let b = try XCTUnwrap(Bundle(path: try XCTUnwrap(
                Bundle.main.path(forResource: lang, ofType: "lproj"))))
            for k in ["tone_retry_mic_unavailable", "tone_retry_no_voice"] {
                XCTAssertNotEqual(b.localizedString(forKey: k, value: nil, table: nil), k,
                                  "\(lang) 缺 \(k)")
            }
        }
    }

    /// 通关线仍为 CLAUDE.md 锁定的 0.6，本次改动不得动它
    func testPassThresholdUnchanged() {
        let d = AspirationDetector()
        let allOn = [[Float]](repeating: [Float](repeating: 1, count: 1600), count: 6)
        XCTAssertGreaterThanOrEqual(d.triggerRate(frames: allOn), 0.6)
    }
}
