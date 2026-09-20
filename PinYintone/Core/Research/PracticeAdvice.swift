import Foundation

/// 「练习建议」的内容与证据（需求 §5、字典 §9）。
///
/// 两条贯穿全文件的红线：
/// - **只用实际分析支持得起的信息**。字典 §9：「总体距离或评分只能支持总体比较，
///   不能推导『第二个音节偏低』等局部诊断」。我们虽有分段 DTW，但那套分段
///   **从未经过验证**——没人确认它真的对应音节级错误，故不作为证据使用
///   （字典的证据码是 `verified_syllable_feature`，「如未实现经核验分析则不得传」）。
/// - **目标词提示不声称用户发生了偏误**。它是「这个词该怎么读」的教学内容，
///   与「这次录得怎么样」分区显示，措辞上不混。
nonisolated struct PracticeAdvice: Equatable {

    /// 字典 §9 source_type，**按实际执行路径记录**
    enum Source: String {
        case teacherHintOnly = "teacher_hint_only"
        case ruleFeedback = "rule_feedback"
        /// 预留：模型输入白名单未批准前不启用，但记录结构已支持
        case aiGenerated = "ai_generated"
    }

    /// 字典 §9 evidence_codes。`none` 与其余**互斥**。
    enum Evidence: String {
        case signalUnusable = "signal_unusable"
        case overallMetric = "overall_metric"
        case verifiedSyllableFeature = "verified_syllable_feature"
        case none
    }

    /// 经教师核对的目标词提示；该词没有已核对提示时为 nil。
    /// **不得套用别词提示**（字典 §9）。
    let teacherHint: String?
    let teacherHintVersion: String?
    /// 本次反馈：每次只突出**一个**主要建议（需求 §5）
    let mainSentenceKey: String
    let source: Source
    let evidence: [Evidence]
    /// 仅 signal_status / metric_name / metric_value，不含任何其它内容
    let evidenceSnapshot: [String: String]

    /// 由本次结果与词条构造。
    /// - Parameters:
    ///   - result: 本次评分；技术失败时传 nil
    ///   - lexemeID: 用于取已核对提示；自由文本传 nil——
    ///     自由文本**不能默认具有**教师核对过的词条提示（需求 §5）
    static func make(result: FeedbackResult?, lexemeID: String?) -> PracticeAdvice {
        let hint = lexemeID.flatMap(ResearchLexicon.approvedHint(for:))

        // 1) 没有可用信号：只说重录，**不做任何发音判断**
        guard let result else {
            return PracticeAdvice(
                teacherHint: hint?.text, teacherHintVersion: hint?.version,
                mainSentenceKey: "advice_retry_no_signal",
                source: hint == nil ? .ruleFeedback : .ruleFeedback,
                evidence: [.signalUnusable],
                evidenceSnapshot: ["signal_status": "unusable"])
        }

        // 2) 有整词指标：只说整词层面的话
        var snapshot = ["signal_status": "usable",
                        "metric_name": "normalized_dtw",
                        "metric_value": String(format: "%.4f", result.dtwScore)]
        let key: String
        if result.levelToneDropped {
            // 平调闸门是**明确计算、有阈值依据的整词特征**，可以据此给出方向建议
            key = "advice_keep_level"
            snapshot["gate"] = "level_tone_fall"
        } else {
            switch result.grade {
            case .excellent, .good: key = "advice_close_to_model"
            case .needsPractice:    key = "advice_listen_and_compare"
            case .fail:             key = "advice_try_again_whole_word"
            }
        }
        return PracticeAdvice(
            teacherHint: hint?.text, teacherHintVersion: hint?.version,
            mainSentenceKey: key, source: .ruleFeedback,
            evidence: [.overallMetric], evidenceSnapshot: snapshot)
    }
}
