import XCTest
@testable import PinYintone

/// 建议内容的红线（需求 §5、字典 §9）。
final class PracticeAdviceTests: XCTestCase {

    private func result(_ dtw: Float, _ grade: FeedbackGrade,
                        gated: Bool = false) -> FeedbackResult {
        FeedbackResult(dtwScore: dtw, levelToneDropped: gated, grade: grade,
                       attemptNumber: 1, segments: [])
    }

    /// 只用整词证据：**绝不出现 verified_syllable_feature**——分段 DTW 未经验证
    func testNeverClaimsSyllableLevelEvidence() {
        for g in [FeedbackGrade.excellent, .good, .needsPractice, .fail] {
            let a = PracticeAdvice.make(result: result(0.3, g), lexemeID: "paobu")
            XCTAssertFalse(a.evidence.contains(.verifiedSyllableFeature),
                           "分段 DTW 未经验证，不得作为音节级证据")
            XCTAssertEqual(a.evidence, [.overallMetric])
        }
    }

    /// 技术失败只说重录，**不做任何发音判断**，也不带整词指标
    func testNoSignalGivesRetryOnlyWithoutMetric() {
        let a = PracticeAdvice.make(result: nil, lexemeID: "paobu")
        XCTAssertEqual(a.evidence, [.signalUnusable])
        XCTAssertEqual(a.mainSentenceKey, "advice_retry_no_signal")
        XCTAssertNil(a.evidenceSnapshot["metric_value"], "无有效信号时不得附带评分")
    }

    /// 证据快照只含允许字段（字典 §9：仅 signal_status / metric_name / metric_value）
    func testEvidenceSnapshotHasOnlyAllowedKeys() {
        let a = PracticeAdvice.make(result: result(0.3, .good), lexemeID: "paobu")
        let allowed: Set<String> = ["signal_status", "metric_name", "metric_value", "gate"]
        XCTAssertTrue(Set(a.evidenceSnapshot.keys).isSubset(of: allowed),
                      "快照混入了未获准的字段：\(a.evidenceSnapshot.keys)")
    }

    /// 词条未经教师核对时**不显示提示**，也不套用别词的
    func testNoTeacherHintWhenLexemeNotApproved() {
        XCTAssertFalse(ResearchLexicon.isApproved("paobu"), "前提：当前词表全部 pending")
        XCTAssertNil(PracticeAdvice.make(result: result(0.3, .good), lexemeID: "paobu").teacherHint)
    }

    /// 自由文本**不能默认具有**教师核对过的词条提示（需求 §5）
    func testFreeTextHasNoTeacherHint() {
        XCTAssertNil(PracticeAdvice.make(result: result(0.3, .good), lexemeID: nil).teacherHint)
    }

    /// 闸门触发时给的是整词方向建议，不归咎到某个字
    func testGatedResultGivesWholeWordDirection() {
        let a = PracticeAdvice.make(result: result(0.2, .fail, gated: true), lexemeID: "paobu")
        XCTAssertEqual(a.mainSentenceKey, "advice_keep_level")
        XCTAssertEqual(a.evidenceSnapshot["gate"], "level_tone_fall")
    }

    /// 四语都有译文，且主建议模板不含占位符（整词建议无可归咎的单字）
    func testAllSentencesLocalizedWithoutPlaceholder() throws {
        let keys = ["advice_retry_no_signal", "advice_keep_level", "advice_close_to_model",
                    "advice_listen_and_compare", "advice_try_again_whole_word",
                    "advice_title", "advice_target_title", "advice_this_time_title"]
        for lang in ["zh-Hans", "en", "fr", "ar"] {
            let b = try XCTUnwrap(Bundle(path: try XCTUnwrap(
                Bundle.main.path(forResource: lang, ofType: "lproj"))))
            for k in keys {
                let v = b.localizedString(forKey: k, value: nil, table: nil)
                XCTAssertNotEqual(v, k, "\(lang) 缺 \(k)")
                XCTAssertFalse(v.contains("%@"), "\(lang) 的 \(k) 不应含占位符")
            }
        }
    }

    /// AI 未启用：当前任何路径都不得标成模型生成
    func testAiPathNotEnabledYet() {
        for gated in [true, false] {
            let a = PracticeAdvice.make(result: result(0.3, .fail, gated: gated), lexemeID: "paobu")
            XCTAssertNotEqual(a.source, .aiGenerated,
                              "模型输入白名单未批准前不得启用 AI 路径")
        }
    }
}

@MainActor
final class AdviceRequestLogTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AdviceRequestLog.shared.clearPendingOnWithdrawal()
        ResearchEventLog.shared.eligibility = .eligible
        ResearchEventLog.shared.window = .init(start: Date().addingTimeInterval(-60),
                                               end: Date().addingTimeInterval(3600))
        ResearchConsent.shared.grant(textVersion: "c1", language: "zh")
    }
    override func tearDown() {
        AdviceRequestLog.shared.clearPendingOnWithdrawal()
        ResearchConsent.shared.withdraw()
        super.tearDown()
    }

    /// 一次点击一行；**未点击不产生记录**
    func testOneRecordPerClick() {
        XCTAssertTrue(AdviceRequestLog.shared.pending.isEmpty, "未点击不得预先生成")
        let a = PracticeAdvice.make(result: nil, lexemeID: nil)
        AdviceRequestLog.shared.record(advice: a, attemptID: UUID(), lexemeVersionID: nil)
        AdviceRequestLog.shared.record(advice: a, attemptID: UUID(), lexemeVersionID: nil)
        XCTAssertEqual(AdviceRequestLog.shared.pending.count, 2)
        XCTAssertEqual(Set(AdviceRequestLog.shared.pending.map(\.requestID)).count, 2)
    }

    /// 模板路径**不声称模型生成**
    func testTemplatePathIsNotMarkedAsAI() {
        AdviceRequestLog.shared.record(
            advice: .make(result: nil, lexemeID: nil), attemptID: nil, lexemeVersionID: nil)
        XCTAssertEqual(AdviceRequestLog.shared.pending.first?.sourceType, "rule_feedback")
    }

    func testNotRecordedWithoutConsent() {
        ResearchConsent.shared.withdraw()
        AdviceRequestLog.shared.record(
            advice: .make(result: nil, lexemeID: nil), attemptID: nil, lexemeVersionID: nil)
        XCTAssertTrue(AdviceRequestLog.shared.pending.isEmpty)
    }
}
