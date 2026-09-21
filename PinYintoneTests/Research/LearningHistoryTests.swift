import XCTest
@testable import PinYintone

/// 学习记录的呈现边界（CLAUDE.md 结果解释边界、问卷核校要求）。
@MainActor
final class LearningHistoryTests: XCTestCase {

    /// 技术失败必须排除：它的分数是哨兵 -1，显示出来会被读成「负分」
    func testHistoryExcludesTechnicalRetries() {
        let history = SessionRepository.shared.fetchHistory()
        for s in history {
            XCTAssertNotEqual(s.resultStatus, ResultStatus.technicalRetry.rawValue,
                              "技术失败不得混进成绩列表")
            XCTAssertGreaterThanOrEqual(s.dtwScore, 0,
                                        "列表里不得出现哨兵分（-1）")
            XCTAssertNotEqual(s.grade, RecordSentinel.noGrade,
                              "列表里不得出现 n/a 等级")
        }
    }

    /// 技术失败单独计数，不与成绩混为一谈
    func testRetryCountIsSeparate() {
        XCTAssertGreaterThanOrEqual(SessionRepository.shared.technicalRetryCount(), 0)
    }

    /// 四语文案齐备，且**不得出现进步/提升/水平**这类表述
    func testCopyDoesNotClaimProgressOrProficiency() throws {
        let banned = [
            "zh-Hans": ["进步", "提升", "水平", "能力"],
            "en": ["improve", "progress", "proficiency", "level of"],
            "fr": ["progrès", "amélior", "niveau de"],
        ]
        let keys = ["history_title", "history_summary", "history_total_practices",
                    "history_words_practiced", "history_recent", "history_empty",
                    "history_footer_note"]
        for (lang, words) in banned {
            let b = try XCTUnwrap(Bundle(path: try XCTUnwrap(
                Bundle.main.path(forResource: lang, ofType: "lproj"))))
            for k in keys {
                let v = b.localizedString(forKey: k, value: nil, table: nil)
                XCTAssertNotEqual(v, k, "\(lang) 缺 \(k)")
                for w in words {
                    XCTAssertFalse(v.lowercased().contains(w.lowercased()),
                                   "\(lang) 的 \(k) 含「\(w)」——学习记录不得表述为能力评定或进步")
                }
            }
        }
    }

    /// 阿拉伯文也要有（不参与禁词检查，但必须存在）
    func testArabicCopyPresent() throws {
        let b = try XCTUnwrap(Bundle(path: try XCTUnwrap(
            Bundle.main.path(forResource: "ar", ofType: "lproj"))))
        for k in ["history_title", "history_footer_note"] {
            XCTAssertNotEqual(b.localizedString(forKey: k, value: nil, table: nil), k)
        }
    }
}
