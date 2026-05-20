import XCTest
@testable import PinYintone

final class ChineseTokenizerTests: XCTestCase {
    var tokenizer: ChineseTokenizer!

    override func setUp() {
        super.setUp()
        tokenizer = ChineseTokenizer()
    }

    override func tearDown() {
        tokenizer = nil
        super.tearDown()
    }

    func testBasicSegmentation() {
        let tokens = tokenizer.tokenize("今天天气很好")
        XCTAssertTrue(tokens.contains("今天"), "应切出「今天」")
        XCTAssertTrue(tokens.contains("天气"), "应切出「天气」")
        // 拼接还原应等于原文（无丢字）
        XCTAssertEqual(tokens.joined(), "今天天气很好")
    }

    func testPunctuationFiltered() {
        let tokens = tokenizer.tokenize("你好！")
        XCTAssertFalse(tokens.contains("！"), "标点应被过滤")
        XCTAssertTrue(tokens.contains("你好"))
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(tokenizer.tokenize(""), [])
    }

    func testWhitespaceFiltered() {
        let tokens = tokenizer.tokenize("你好 世界")
        // 不假设具体分词粒度，只校验空白被剔除、无丢字
        XCTAssertFalse(tokens.contains(where: { $0.contains(" ") }), "词条不应包含空格")
        XCTAssertFalse(tokens.contains(""), "不应有空词条")
        XCTAssertEqual(tokens.joined(), "你好世界", "去除空格后应无丢字")
    }
}
