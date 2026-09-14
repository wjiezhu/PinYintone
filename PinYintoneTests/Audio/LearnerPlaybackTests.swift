import AVFoundation
import XCTest
@testable import PinYintone

/// 回听的播放链路。存储逻辑另有测试覆盖，这里验证**真的能放出声**——
/// 此前因模拟器无音频输入，这条路径只验证过「能编译」。
@MainActor
final class LearnerPlaybackTests: XCTestCase {

    /// 合成 440 Hz 正弦，16 kHz 单声道，与 AudioEngine 的输出格式一致
    private func tone(seconds: Double = 0.3) -> [Int16] {
        let n = Int(16_000 * seconds)
        return (0..<n).map { i in
            Int16(sin(2 * .pi * 440 * Double(i) / 16_000) * 8000)
        }
    }

    override func tearDown() {
        LearnerAudioPlayer.shared.stop()
        LearnerRecordingStore.shared.clear()
        super.tearDown()
    }

    func testPlaybackActuallyStarts() throws {
        let started = try LearnerAudioPlayer.shared.play(pcm: tone(), sampleRate: 16_000)
        XCTAssertTrue(started,
                      "play() 必须如实报告是否真的开始播放——埋点 learner_audio_started 依赖它")
        XCTAssertTrue(LearnerAudioPlayer.shared.isPlaying)
    }

    func testStopHaltsPlayback() throws {
        _ = try LearnerAudioPlayer.shared.play(pcm: tone(seconds: 2), sampleRate: 16_000)
        LearnerAudioPlayer.shared.stop()
        XCTAssertFalse(LearnerAudioPlayer.shared.isPlaying)
    }

    /// 端到端：存入录音 → 回听放出来
    func testStoreThenReplay() throws {
        let store = LearnerRecordingStore.shared
        store.store(pcm: tone(seconds: 1), lexemeID: "canjia")
        XCTAssertTrue(store.hasRecording)

        let started = try LearnerAudioPlayer.shared.play(pcm: store.pcm,
                                                        sampleRate: store.sampleRate)
        XCTAssertTrue(started, "存进去的录音应当能回放")
    }

    /// 放完回听后仍能录音——回听会把会话切到 .playback
    func testRecordingStillWorksAfterReplay() throws {
        _ = try LearnerAudioPlayer.shared.play(pcm: tone(), sampleRate: 16_000)
        LearnerAudioPlayer.shared.stop()

        let engine = AudioEngine()
        do {
            try engine.start()
        } catch {
            throw XCTSkip("当前环境无可用音频输入：\(error)")
        }
        XCTAssertTrue(engine.isRecording, "回听之后必须还能录音")
        engine.stop()
    }
}
