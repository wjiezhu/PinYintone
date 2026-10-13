import CoreData
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
        let keys = ["history_title", "history_empty", "history_empty_filtered",
                    "history_footer_note", "history_filter", "history_filter_all",
                    "history_kind_fixed", "history_kind_free", "history_kind_self_test",
                    "history_status_recorded", "history_status_technical",
                    "tab_history", "result_title", "result_try_again",
                    "self_test_done_title", "self_test_done_body"]
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

    // MARK: - 记录行（需求 U05）

    private func session(grade: String = "good", score: Double = 0.3, phase: String? = "training",
                         status: ResultStatus = .validResult) -> TrainingSession {
        let s = TrainingSession(context: CoreDataStack.shared.context)
        s.id = UUID()
        s.deviceID = "d"
        s.role = "student"
        s.groupAssignment = "n/a"
        s.lexemeID = "canjia"
        s.dtwScore = score
        s.grade = grade
        s.attemptNumber = 1
        s.timestamp = Date()
        s.phase = phase
        s.resultStatus = status.rawValue
        return s
    }

    /// 技术失败**单独标记**：按 resultStatus 识别，不看分数，更不显示成低分
    func testTechnicalFailureIsFlaggedSeparatelyNotShownAsALowScore() {
        let failed = session(grade: RecordSentinel.noGrade, score: RecordSentinel.noScore,
                             status: .technicalRetry)
        defer { CoreDataStack.shared.context.rollback() }
        let entry = HistoryEntry(session: failed) { _ in "参加" }
        XCTAssertEqual(entry.status, .technicalFailure)
        XCTAssertNotEqual(entry.status, .notPassed, "技术失败不是「未通过」")
        XCTAssertEqual(entry.kind, .fixedWord)
    }

    func testPracticeRowsShowPassOrTryAgain() {
        defer { CoreDataStack.shared.context.rollback() }
        XCTAssertEqual(HistoryEntry(session: session(grade: "good")) { $0 }.status, .passed)
        XCTAssertEqual(HistoryEntry(session: session(grade: "fail")) { $0 }.status, .notPassed)
    }

    /// 自测本来就不给评价，记录页也不补给——哪怕库里存着它的成绩
    func testSelfTestRowsNeverRevealPassOrFail() {
        defer { CoreDataStack.shared.context.rollback() }
        for phase in ["self_test", "pretest", "posttest"] {
            for grade in ["excellent", "fail"] {
                let entry = HistoryEntry(session: session(grade: grade, phase: phase)) { $0 }
                XCTAssertEqual(entry.kind, .selfTest, phase)
                XCTAssertEqual(entry.status, .recorded, "\(phase)/\(grade) 泄露了评价")
            }
        }
    }

    /// 自测的技术失败同样单独标记
    func testSelfTestTechnicalFailureIsStillFlagged() {
        defer { CoreDataStack.shared.context.rollback() }
        let entry = HistoryEntry(session: session(grade: RecordSentinel.noGrade,
                                                  score: RecordSentinel.noScore,
                                                  phase: "self_test", status: .technicalRetry)) { $0 }
        XCTAssertEqual(entry.status, .technicalFailure)
    }

    func testThreeKindsAreFilterable() {
        XCTAssertEqual(HistoryEntry.Kind.allCases, [.fixedWord, .freeText, .selfTest])
    }
}
