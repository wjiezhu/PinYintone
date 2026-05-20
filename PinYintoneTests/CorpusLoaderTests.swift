import XCTest
@testable import PinYintone

final class CorpusLoaderTests: XCTestCase {

    func testCorpusLoadsTwentyWords() {
        // 验证 lexemes.json 解码成功且为 20 词（捕获 JSON schema 错误）
        XCTAssertEqual(CorpusLoader.shared.loadLexemes().count, 20)
    }

    func testCategorySplit() {
        XCTAssertEqual(CorpusLoader.shared.lexemes(in: .aspiration).count, 6, "送气关卡 6 词")
        XCTAssertEqual(CorpusLoader.shared.lexemes(in: .tone).count, 14, "声调关卡 14 词")
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
