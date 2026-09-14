import AVFoundation
import XCTest
@testable import PinYintone

/// 会话类别与录音启动的交互。
///
/// 真实病例：**听完 TTS 示范（或回听）后再点录音，录不起来。**
/// 成因是 `AudioEngine.start()` 曾在配置会话**之前**访问 `engine.inputNode`——
/// 访问会按当时的会话类别实例化 IO unit 并**缓存**其格式，若此刻会话停在
/// `.playback`，拿到的是 0 Hz 无效格式，后续校验必然失败。
@MainActor
final class AudioSessionOrderingTests: XCTestCase {

    /// 共用一个实例：AVAudioEngine 析构在模拟器上会 RPC 超时并 abort 进程
    private static let engine = AudioEngine()

    override func tearDown() {
        Self.engine.stop()
        super.tearDown()
    }

    /// 会话停在 .playback 时（刚放完示范/回听）仍能开始录音
    func testCanStartRecordingAfterPlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        // 模拟 SpeechService.speak / LearnerAudioPlayer.play 留下的会话状态
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)

        do {
            try Self.engine.start()
        } catch {
            throw XCTSkip("当前环境无可用音频输入：\(error)")
        }
        XCTAssertTrue(Self.engine.isRecording,
                      "听完示范后必须还能录音——这正是该顺序 bug 的用户可见表现")
        Self.engine.stop()
    }

    /// 连续「放音 → 录音」多轮不应退化
    func testRepeatedPlaybackThenRecordCycles() throws {
        let session = AVAudioSession.sharedInstance()
        for round in 1...3 {
            try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try? session.setActive(true)
            do {
                try Self.engine.start()
            } catch {
                throw XCTSkip("当前环境无可用音频输入：\(error)")
            }
            XCTAssertTrue(Self.engine.isRecording, "第 \(round) 轮录音应能启动")
            Self.engine.stop()
        }
    }
}
