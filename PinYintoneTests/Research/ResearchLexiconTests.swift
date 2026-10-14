import XCTest
@testable import PinYintone

/// 研究词表映射。历史缺陷：曾把稳定编号当版本编号上报，外键全部悬空。
final class ResearchLexiconTests: XCTestCase {

    /// 研究词表必须真的随包发布（走 Bundle.main，与 App 实际加载路径一致）
    func testLexiconShipsInAppBundle() {
        XCTAssertNotNil(ResearchLexicon.lexiconVersion, "research_lexicon.json 未随包发布")
    }

    /// 语料里每个词都必须有版本编号，否则它的练习记录会带 nil 词条外键
    func testEveryCorpusLexemeHasVersionID() {
        let lexemes = CorpusLoader.shared.loadLexemes()
        XCTAssertFalse(lexemes.isEmpty)
        for lex in lexemes {
            XCTAssertNotNil(ResearchLexicon.versionID(for: lex.id),
                            "\(lex.hanzi)(\(lex.id)) 在研究词表中没有版本编号")
        }
    }

    /// 核心回归：版本编号**不是**稳定编号
    func testVersionIDIsNotTheStableID() {
        for lex in CorpusLoader.shared.loadLexemes() {
            XCTAssertNotEqual(ResearchLexicon.versionID(for: lex.id), lex.id,
                              "把稳定编号当版本编号上报会让外键全部悬空")
        }
    }

    /// 未知词条返回 nil，**不回退成稳定编号**
    func testUnknownLexemeReturnsNilNotFallback() {
        XCTAssertNil(ResearchLexicon.versionID(for: "no_such_word"))
        XCTAssertNil(ResearchLexicon.versionID(for: nil))
    }

    /// 版本编号全局唯一
    func testVersionIDsAreUnique() {
        let ids = CorpusLoader.shared.loadLexemes()
            .compactMap { ResearchLexicon.versionID(for: $0.id) }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    /// 正式采集要求全部词条经核对（字典 §6）：lex-2026.10 由研究者 2026-10-14 确认。
    /// 词表版本不得带 draft——服务端冻结正式配置时会拒绝。
    func testShippedLexiconIsApprovedForFormalCollection() {
        XCTAssertEqual(ResearchLexicon.lexiconVersion, "lex-2026.10")
        XCTAssertFalse(ResearchLexicon.lexiconVersion?.contains("draft") ?? true)
        for lex in CorpusLoader.shared.loadLexemes() {
            XCTAssertTrue(ResearchLexicon.isApproved(lex.id), "\(lex.hanzi)(\(lex.id)) 未标记为已核对")
        }
    }
}
