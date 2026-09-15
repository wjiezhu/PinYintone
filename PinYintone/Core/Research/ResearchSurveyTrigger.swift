import Combine
import Foundation

/// 问卷邀请时机（字典 §3 `post_trigger_*`、§10 `timing_class`、验收场景 §15）。
///
/// 计数口径来自研究者已确认的定义，四条都容易做错：
/// - **只算「分析成功且结果已实际显示」的固定词条练习**。第 5 次分析成功
///   但结果没显示出来，不算，也不弹问卷。
/// - **不要求评分通过**。没通关照样计次。
/// - **同词重录可累计**，不要求 5 个不同词。
/// - **自由文本不计入**。
///
/// 计数按 `attempt_id` 去重：同一次练习的结果重复渲染（旋转屏幕、返回再进）
/// 不得重复计次。
@MainActor
final class ResearchSurveyTrigger: ObservableObject {
    static let shared = ResearchSurveyTrigger()

    private enum Key {
        static let counted = "pt_research_qualifying_attempts"
        static let countedIDs = "pt_research_counted_attempt_ids"
        static let postInvited = "pt_research_post_invited"
        static let preInvited = "pt_research_pre_invited"
        static let firstAttemptStarted = "pt_research_first_attempt_started"
    }

    /// 达到即邀请。由 manifest 下发（研究者已确认为 5），下发不到时不邀请。
    private(set) var threshold: Int = 5

    private init() {}

    // MARK: - 合格练习计数

    var qualifyingCount: Int { UserDefaults.standard.integer(forKey: Key.counted) }

    private var countedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Key.countedIDs) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Key.countedIDs) }
    }

    /// 记一次合格练习。返回是否**恰好**在本次达到阈值（用于只邀请一次）。
    @discardableResult
    func recordQualifyingAttempt(_ attemptID: UUID,
                                 taskType: ResearchAttemptRecord.TaskType,
                                 resultDisplayed: Bool) -> Bool {
        // 自由文本不计入；结果未显示不计入
        guard taskType == .fixedWord, resultDisplayed else { return false }
        let key = attemptID.uuidString
        var ids = countedIDs
        guard !ids.contains(key) else { return false }   // 同一次练习只计一次
        ids.insert(key)
        countedIDs = ids

        let n = qualifyingCount + 1
        UserDefaults.standard.set(n, forKey: Key.counted)
        return n == threshold && !hasInvitedPost
    }

    func configure(threshold: Int) { self.threshold = threshold }

    // MARK: - 邀请状态

    var hasInvitedPost: Bool { UserDefaults.standard.bool(forKey: Key.postInvited) }
    func markPostInvited() { UserDefaults.standard.set(true, forKey: Key.postInvited) }

    var hasInvitedPre: Bool { UserDefaults.standard.bool(forKey: Key.preInvited) }
    func markPreInvited() { UserDefaults.standard.set(true, forKey: Key.preInvited) }

    /// 是否该邀请前置问卷：还没邀请过，且还没开始过任何练习。
    var shouldInvitePre: Bool { !hasInvitedPre && !hasStartedAnyAttempt }

    // MARK: - 前置问卷的时间定位

    var hasStartedAnyAttempt: Bool {
        UserDefaults.standard.bool(forKey: Key.firstAttemptStarted)
    }

    func markFirstAttemptStarted() {
        UserDefaults.standard.set(true, forKey: Key.firstAttemptStarted)
    }

    /// 前置问卷的 `timing_class`。
    ///
    /// 已经开始练习后才提交的，标 `late_pre`——**不能算作练习前调查**
    /// （字典 §10、问卷 §3：错过该时点不补录为「前置」）。
    var preTimingClass: String {
        hasStartedAnyAttempt ? "late_pre" : "before_first_attempt"
    }

    /// 撤回研究时清空本地计数与邀请状态
    func reset() {
        let d = UserDefaults.standard
        [Key.counted, Key.countedIDs, Key.postInvited,
         Key.preInvited, Key.firstAttemptStarted].forEach { d.removeObject(forKey: $0) }
    }
}
