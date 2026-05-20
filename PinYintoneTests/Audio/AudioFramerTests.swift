import XCTest
@testable import PinYintone

final class AudioFramerTests: XCTestCase {

    func testFrameSizeAndHop() {
        let framer = AudioFramer(frameSize: 512, hopSize: 128)
        var frames: [[Float]] = []
        framer.onFrame = { frames.append($0) }

        // 喂入 1600 个 16-bit 采样（0.1s）
        framer.feed([Int16](repeating: 16384, count: 1600))

        // 1600 起，每帧后移除 128，直到 < 512：1600,1472,...,576 共 9 帧
        XCTAssertEqual(frames.count, 9, "512/128 帧化应产出 9 帧")
        XCTAssertTrue(frames.allSatisfy { $0.count == 512 }, "每帧应为 512 样本")
        // 16384/32768 = 0.5
        XCTAssertEqual(frames[0][0], 0.5, accuracy: 1e-4, "应归一化为 [-1,1]")
    }

    func testInsufficientSamplesNoFrame() {
        let framer = AudioFramer()
        var count = 0
        framer.onFrame = { _ in count += 1 }
        framer.feed([Int16](repeating: 0, count: 256))   // < 512
        XCTAssertEqual(count, 0, "不足一帧不应回调")
    }

    func testResetClearsBuffer() {
        let framer = AudioFramer()
        var count = 0
        framer.onFrame = { _ in count += 1 }
        framer.feed([Int16](repeating: 0, count: 400))   // 残留 400
        framer.reset()
        framer.feed([Int16](repeating: 0, count: 200))   // 200，若未清空则 600≥512 会触发
        XCTAssertEqual(count, 0, "reset 后残留应被清空")
    }

    func testAccumulationAcrossChunks() {
        let framer = AudioFramer(frameSize: 512, hopSize: 512)  // 无重叠便于计数
        var frames: [[Float]] = []
        framer.onFrame = { frames.append($0) }
        framer.feed([Int16](repeating: 1, count: 300))   // 300
        framer.feed([Int16](repeating: 1, count: 300))   // 600 → 1 帧，残留 88
        XCTAssertEqual(frames.count, 1, "跨分片累积应正确凑帧")
    }
}
