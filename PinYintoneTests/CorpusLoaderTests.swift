import XCTest
@testable import PinYintone

final class CorpusLoaderTests: XCTestCase {

    func testCorpusLoadsAllWords() {
        // 验证 lexemes.json 解码成功（捕获 JSON schema 错误）。2026-11-18 由 20 词扩充，11-19 配平后 170 词
        XCTAssertEqual(CorpusLoader.shared.loadLexemes().count, 170)
    }

    func testCategorySplit() {
        XCTAssertEqual(CorpusLoader.shared.lexemes(in: .aspiration).count, 72, "送气关卡 72 词")
        XCTAssertEqual(CorpusLoader.shared.lexemes(in: .tone).count, 98, "声调关卡 98 词")
    }

    // MARK: - 2026-11-18 扩充

    func testIDsAndHanziAreUnique() {
        let words = CorpusLoader.shared.loadLexemes()
        XCTAssertEqual(Set(words.map(\.id)).count, words.count)
        XCTAssertEqual(Set(words.map(\.hanzi)).count, words.count)
    }

    /// 四个声调两两组合的 16 种**各 6 个词**（研究者 2026-11-19 决定配平；扩充前只有 7 种，且没有二声）
    func testAllSixteenToneCombinationsAreCovered() {
        var counts: [String: Int] = [:]
        for word in CorpusLoader.shared.lexemes(in: .tone) {
            counts["\(word.tones[0])+\(word.tones[1])", default: 0] += 1
        }
        for first in 1...4 {
            for second in 1...4 {
                XCTAssertEqual(counts["\(first)+\(second)"] ?? 0, 6, "\(first)+\(second) 没有配平到 6 个")
            }
        }
    }

    /// 扩充的词都是双音节、不含轻声（研究者 2026-11-18 决定去掉候选里的轻声词），各语言释义齐全
    func testExpansionWordsAreDisyllabicWithoutNeutralTone() {
        let original: Set<String> = ["paobu", "bangzhu", "tingdong", "dengdai", "kaoshi", "gaosu",
                                     "xianzai", "dianshi", "sushe", "hanzi", "heshui", "shenti", "jingli",
                                     "yisheng", "qingchu", "xiuxi", "ziji", "canjia", "zaocan", "xiangxin"]
        let added = CorpusLoader.shared.loadLexemes().filter { !original.contains($0.id) }
        XCTAssertEqual(added.count, 150)
        for word in added {
            XCTAssertEqual(word.tones.count, 2, word.id)
            XCTAssertEqual(word.hanzi.count, 2, word.id)
            XCTAssertEqual(word.pinyin.split(separator: " ").count, 2, word.id)
            XCTAssertFalse(word.tones.contains(5), "\(word.id) 含轻声")
            XCTAssertTrue(word.tones.allSatisfy { (1...4).contains($0) }, word.id)
            for gloss in [word.french, word.darija, word.spanish ?? "", word.italian ?? "", word.english ?? ""] {
                XCTAssertFalse(gloss.isEmpty, "\(word.id) 缺释义")
            }
            if word.category == .tone {
                XCTAssertEqual(word.wordSet, .expansion, "\(word.id) 不得混进旧词集或自测词集")
            }
        }
    }

    /// 送气词都写明考察的声母与方向，声母就是拼音的开头；12 个声母**各 6 个词**（研究者 2026-11-19 决定配平）
    func testEveryAspirationWordDeclaresItsTarget() {
        let aspirated: Set<String> = ["p", "t", "k", "c", "ch", "q"]
        let unaspirated: Set<String> = ["b", "d", "g", "z", "zh", "j"]
        var perInitial: [String: Int] = [:]
        for word in CorpusLoader.shared.lexemes(in: .aspiration) {
            guard let target = word.aspirationTarget else {
                XCTFail("\(word.id) 缺 aspirationTarget"); continue
            }
            XCTAssertTrue(word.id.hasPrefix(target.initial), word.id)
            if target.initial.count == 1 {
                XCTAssertFalse(word.id.hasPrefix(target.initial + "h"), "\(word.id) 的声母写错了")
            }
            XCTAssertEqual(target.aspirated, aspirated.contains(target.initial), word.id)
            XCTAssertTrue(aspirated.union(unaspirated).contains(target.initial), word.id)
            perInitial[target.initial, default: 0] += 1
        }
        for initial in aspirated.union(unaspirated) {
            XCTAssertEqual(perInitial[initial] ?? 0, 6, "\(initial) 没有配平到 6 个")
        }
    }

    /// 自测词集没有因为扩充而变化（`assess-v1` 不变）
    func testAssessmentSetIsUnchangedByTheExpansion() {
        XCTAssertEqual(Set(CorpusLoader.shared.assessmentPool().map(\.id)),
                       ["xiangxin", "heshui", "sushe", "hanzi"])
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
