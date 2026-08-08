import XCTest
@testable import PinYintone

final class CorpusLoaderTests: XCTestCase {

    func testCorpusLoadsAllWords() {
        // 6 送气 + 10 测试 + 8 A + 8 B = 32（捕获 JSON schema 错误）
        XCTAssertEqual(CorpusLoader.shared.loadLexemes().count, 32)
    }

    func testCategorySplit() {
        XCTAssertEqual(CorpusLoader.shared.lexemes(in: .aspiration).count, 6, "送气关卡 6 词")
        XCTAssertEqual(CorpusLoader.shared.lexemes(in: .tone).count, 26, "声调关卡 26 词（10 测试 + 16 训练）")
    }

    // MARK: - 受试内前后测词表结构

    func testTestWordsAreTenAndFixedOrder() {
        let test = CorpusLoader.shared.testWords()
        XCTAssertEqual(test.count, 10, "前后测 10 词")
        XCTAssertEqual(test.first?.id, "gongsi", "测试词固定首词")
        XCTAssertTrue(test.allSatisfy { $0.subset == .test })
    }

    func testTrainingSubsetsAreEightEach() {
        XCTAssertEqual(CorpusLoader.shared.trainingWords(subset: .trainingA).count, 8)
        XCTAssertEqual(CorpusLoader.shared.trainingWords(subset: .trainingB).count, 8)
    }

    func testTestWordsNotInTrainingPool() {
        // P1-5#2：前后测词不得出现在训练池
        let trainingIDs = Set(CorpusLoader.shared.orderedPool(category: .tone).map(\.id))
        let testIDs = Set(CorpusLoader.shared.testWords().map(\.id))
        XCTAssertTrue(trainingIDs.isDisjoint(with: testIDs), "测试词与训练词零重叠")
        XCTAssertEqual(trainingIDs.count, 16, "训练池 = A8 + B8")
    }

    func testAspirationFirstWord() {
        let first = CorpusLoader.shared.lexemes(in: .aspiration).first
        XCTAssertEqual(first?.hanzi, "跑步")
        XCTAssertEqual(first?.tones, [3, 4])
        XCTAssertFalse(first?.french.isEmpty ?? true, "应含法语释义")
        XCTAssertFalse(first?.darija.isEmpty ?? true, "应含 Darija 对译")
    }

    func testNextLexemeCyclesWithinCategory() {
        // 连续取送气词应只返回送气类别，且循环不越界
        for _ in 0..<10 {
            XCTAssertEqual(CorpusLoader.shared.nextLexeme(category: .aspiration).category, .aspiration)
        }
    }
}
