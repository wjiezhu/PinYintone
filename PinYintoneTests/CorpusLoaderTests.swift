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

    // MARK: - 词集划分（升级需求 §3.2）

    func testEveryToneLexemeHasWordSet() {
        for lex in CorpusLoader.shared.lexemes(in: .tone) {
            XCTAssertNotNil(lex.wordSet, "\(lex.id) 缺 wordSet，会落到无条件分支")
        }
    }

    func testAssessmentSetDisjointFromTrainingSets() {
        // 前后测词集与训练词集不重叠——增益比较的前提
        let assessment = Set(CorpusLoader.shared.assessmentPool().map(\.id))
        let training = Set(WordSet.trainingSets
            .flatMap { CorpusLoader.shared.tonePool(wordSet: $0) }.map(\.id))
        XCTAssertFalse(assessment.isEmpty)
        XCTAssertFalse(training.isEmpty)
        XCTAssertTrue(assessment.isDisjoint(with: training), "测试词集不得与训练词集重叠")
    }

    func testTrainingSetsAreDifficultyMatched() {
        // 两个训练词集的"声调组合"必须逐一配对，否则条件效应会被难度差淹没。
        // 唯一允许的例外：4+3 与 3+1 同属"降升混合"，视为等难度配对。
        func normalized(_ set: WordSet) -> [[Int]] {
            CorpusLoader.shared.tonePool(wordSet: set)
                .map { $0.tones == [4, 3] || $0.tones == [3, 1] ? [9, 9] : $0.tones }
                .sorted { "\($0)" < "\($1)" }
        }
        XCTAssertEqual(CorpusLoader.shared.tonePool(wordSet: .set1).count,
                       CorpusLoader.shared.tonePool(wordSet: .set2).count,
                       "两训练词集词数应相同")
        XCTAssertEqual(normalized(.set1), normalized(.set2), "两训练词集的声调组合应逐一配对")
    }

    func testNextLexemeCyclesWithinCategory() {
        // 连续取送气词应只返回送气类别，且循环不越界
        for _ in 0..<10 {
            XCTAssertEqual(CorpusLoader.shared.nextLexeme(category: .aspiration).category, .aspiration)
        }
    }
}
