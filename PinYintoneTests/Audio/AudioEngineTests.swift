import XCTest
@testable import PinYintone

final class AudioEngineTests: XCTestCase {

    // MARK: - 固定参数（CLAUDE.md）

    func testFixedParameters() {
        let engine = AudioEngine()
        XCTAssertEqual(engine.sampleRate, 16_000, "采样率固定 16 kHz")
        XCTAssertEqual(engine.chunkSize, 1600, "每次回调 1600 采样 = 0.1s")
    }

    func testInitialState() {
        let engine = AudioEngine()
        XCTAssertFalse(engine.isRecording, "初始未录音")
        XCTAssertEqual(engine.currentTime, 0, "初始时长为 0")
    }

    // MARK: - 16-bit → Float 归一化

    func testFloatSamplesConversion() {
        XCTAssertEqual(AudioEngine.floatSamples(from: [0]).first, 0, "0 → 0.0")
        XCTAssertEqual(AudioEngine.floatSamples(from: [16384]).first!, 0.5, accuracy: 1e-4,
                       "16384 → ≈0.5")
        XCTAssertEqual(AudioEngine.floatSamples(from: [Int16.min]).first!, -1.0, accuracy: 1e-6,
                       "Int16.min → -1.0")
        XCTAssertEqual(AudioEngine.floatSamples(from: []).count, 0, "空输入 → 空输出")
    }

    // MARK: - 异步：stop() 触发 onFinish（expectation）

    func testStopFiresOnFinishAsync() throws {
        // 模拟器上这两个测试不可靠：当宿主音频恰好返回有效输入格式时，引擎会真的启动，
        // 而 AVAudioEngine 析构时要跟音频守护进程做 RPC 拆除 AURemoteIO，
        // 模拟器里该 RPC 会超时，AudioToolbox 直接 abort() 整个进程
        // （_ReportRPCTimeout → SIGABRT）。崩溃不计入断言失败，xcodebuild 会报
        // "0 failures" 却 TEST FAILED，把**真正的**失败一起盖掉。
        // 格式无效时则正常 skip，于是同一套代码时好时坏。
        // 真机上 RPC 正常，故只在模拟器跳过，设备上照跑。
        #if targetEnvironment(simulator)
        throw XCTSkip("模拟器音频拆除会 RPC 超时并 abort 进程，改在真机验证")
        #endif

        let engine = AudioEngine()
        do {
            try engine.start()
        } catch {
            throw XCTSkip("当前环境无可用音频输入：\(error)")
        }
        XCTAssertTrue(engine.isRecording, "start() 后应处于录音状态")

        let finished = expectation(description: "onFinish 在主线程异步触发")
        engine.onFinish = { _ in finished.fulfill() }

        let buffer = engine.stop()
        wait(for: [finished], timeout: 3)

        XCTAssertFalse(engine.isRecording, "stop() 后应停止录音")
        XCTAssertNotNil(buffer, "stop() 应返回完整 PCM 缓冲")
    }

    // MARK: - 异步：定时录音返回正确长度的 PCM（expectation）

    func testTimedRecordingProducesExpectedSampleCount() throws {
        // 模拟器上这两个测试不可靠：当宿主音频恰好返回有效输入格式时，引擎会真的启动，
        // 而 AVAudioEngine 析构时要跟音频守护进程做 RPC 拆除 AURemoteIO，
        // 模拟器里该 RPC 会超时，AudioToolbox 直接 abort() 整个进程
        // （_ReportRPCTimeout → SIGABRT）。崩溃不计入断言失败，xcodebuild 会报
        // "0 failures" 却 TEST FAILED，把**真正的**失败一起盖掉。
        // 格式无效时则正常 skip，于是同一套代码时好时坏。
        // 真机上 RPC 正常，故只在模拟器跳过，设备上照跑。
        #if targetEnvironment(simulator)
        throw XCTSkip("模拟器音频拆除会 RPC 超时并 abort 进程，改在真机验证")
        #endif

        let engine = AudioEngine()
        let duration: TimeInterval = 0.4
        let finished = expectation(description: "定时录音结束")
        var produced: [Int16] = []
        engine.onFinish = { pcm in
            produced = pcm
            finished.fulfill()
        }
        do {
            try engine.start(duration: duration)
        } catch {
            throw XCTSkip("当前环境无可用音频输入：\(error)")
        }

        let result = XCTWaiter().wait(for: [finished], timeout: 5)
        try XCTSkipIf(result != .completed, "模拟器未提供音频输入，跳过时长断言")

        // 16 kHz × 0.4s = 6400 采样，允许少量边界误差
        XCTAssertEqual(produced.count, Int(duration * 16_000), accuracy: 1600,
                       "返回 PCM 长度应对应 16kHz × 时长")
    }
}
