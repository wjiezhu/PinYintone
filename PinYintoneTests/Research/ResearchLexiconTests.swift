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

    /// lex-2026.10 的 20 词由研究者 2026-10-14 确认，扩充后仍是已核对，版本编号也没有变。
    /// 2026-11-18 扩充、11-19 配平后的 150 个新词还没有逐词核对：词表版本带 draft（服务端因此不会冻结成正式配置），
    /// 新词不得标成已核对——**核对只能由研究者本人做**。
    func testOnlyResearcherReviewedWordsAreApproved() {
        XCTAssertEqual(ResearchLexicon.lexiconVersion, "lex-2026.11-draft")
        let reviewed: Set<String> = ["paobu", "bangzhu", "tingdong", "dengdai", "kaoshi", "gaosu",
                                     "xianzai", "dianshi", "sushe", "hanzi", "heshui", "shenti", "jingli",
                                     "yisheng", "qingchu", "xiuxi", "ziji", "canjia", "zaocan", "xiangxin"]
        for lex in CorpusLoader.shared.loadLexemes() {
            XCTAssertEqual(ResearchLexicon.isApproved(lex.id), reviewed.contains(lex.id),
                           "\(lex.hanzi)(\(lex.id)) 的核对状态不对")
        }
        XCTAssertEqual(ResearchLexicon.versionID(for: "paobu"), "c5184b45-4e86-4d92-9aae-d4dc67f2dfb1",
                       "已冻结词条的版本编号不得变")
        XCTAssertEqual(ResearchLexicon.versionID(for: "xiangxin"), "e234b115-95fb-493f-b3d1-5dc882db1a1d")
    }
}
