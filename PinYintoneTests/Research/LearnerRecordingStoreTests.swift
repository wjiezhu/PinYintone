import XCTest
@testable import PinYintone

/// 回听的录音暂存。保留策略（决定 17）：只留当前一条，换词/重录即覆盖，退出即清。
@MainActor
final class LearnerRecordingStoreTests: XCTestCase {

    private let store = LearnerRecordingStore.shared

    /// 生成 n 秒的 16 kHz PCM
    private func pcm(seconds: Double) -> [Int16] {
        [Int16](repeating: 1000, count: Int(16_000 * seconds))
    }

    override func setUp() { super.setUp(); store.clear() }
    override func tearDown() { store.clear(); super.tearDown() }

    func testStoresAndReportsAvailability() {
        XCTAssertFalse(store.hasRecording)
        store.store(pcm: pcm(seconds: 1), lexemeID: "canjia")
        XCTAssertTrue(store.hasRecording)
        XCTAssertEqual(store.lexemeID, "canjia")
        XCTAssertEqual(store.pcm.count, 16_000)
    }

    func testOnlyOneRecordingKept() {
        store.store(pcm: pcm(seconds: 1), lexemeID: "canjia")
        store.store(pcm: pcm(seconds: 2), lexemeID: "canjia")
        XCTAssertEqual(store.pcm.count, 32_000, "重录应覆盖而非追加")
    }

    func testWordChangeClearsRecording() {
        store.store(pcm: pcm(seconds: 1), lexemeID: "canjia")
        store.clearIfLexemeChanged(to: "yisheng")
        XCTAssertFalse(store.hasRecording, "换词必须清掉，否则会放出上一个词的录音")
    }

    func testSameWordKeepsRecording() {
        store.store(pcm: pcm(seconds: 1), lexemeID: "canjia")
        store.clearIfLexemeChanged(to: "canjia")
        XCTAssertTrue(store.hasRecording, "同一个词不应清除")
    }

    func testTooShortRecordingIsNotStored() {
        // 没录上的不存，否则回听会放出一段噪声让人以为功能坏了
        store.store(pcm: pcm(seconds: 0.1), lexemeID: "canjia")
        XCTAssertFalse(store.hasRecording)
    }

    func testClearWipesEverything() {
        store.store(pcm: pcm(seconds: 1), lexemeID: "canjia")
        store.clear()
        XCTAssertFalse(store.hasRecording)
        XCTAssertTrue(store.pcm.isEmpty)
        XCTAssertNil(store.lexemeID)
    }

    /// 空录音必须抛错而不是静默返回「已播放」——
    /// 字典要求「只点击播放但播放失败不记 audio_started」
    func testPlayingEmptyRecordingThrows() {
        XCTAssertThrowsError(try LearnerAudioPlayer.shared.play(pcm: [], sampleRate: 16_000))
    }
}
