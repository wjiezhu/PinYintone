import XCTest
@testable import Pinyintone

final class ChineseTokenizerTests: XCTestCase {
    var tokenizer: ChineseTokenizer!

    override func setUp() {
        super.setUp()
        tokenizer = ChineseTokenizer()
    }

    func testBasicSegmentation() {
        // 「今天天气很好」→ 包含"今天"和"天气"（合理分词）
        fatalError("TODO: 实现")
    }

    func testPunctuationFiltered() {
        // 「你好！」→ ["你好"]，叹号被过滤
        fatalError("TODO: 实现")
    }

    func testEmptyInputReturnsEmpty() {
        // 空字符串返回空数组
        fatalError("TODO: 实现")
    }

    func testWhitespaceFiltered() {
        // 「你好 世界」中的空格不作为词条输出
        fatalError("TODO: 实现")
    }
}
