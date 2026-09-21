import Combine
import Foundation

/// 积分（需求 §4、字典 §13）。
///
/// **由配置开关控制**：`manifest.reward_rule_version` 为空时整个功能关闭。
/// 需求原文标注「积分规则待确认」，所以规则版本不写死在代码里——
/// 研究者用种子脚本填一个版本号才启用，且该版本随每条发放记录入库。
///
/// 三条硬隔离（字典 §13 明令）：
/// - **不因问卷完成、研究同意或答案倾向发分**。本类型不引用任何问卷/同意状态。
/// - **未参加研究者照常拿业务积分**，只是不生成研究镜像。
/// - 业务发放与研究镜像**共用同一幂等标识**（attemptID + 规则版本），
///   不会出现一边发了一边没记。
///
/// ⚠ 积分**不是**声调能力或教学效果指标，导出与论文中不得如此解读。
@MainActor
final class RewardLedger: ObservableObject {
    static let shared = RewardLedger()

    private enum Key {
        static let total = "pt_reward_total"
        static let awardedKeys = "pt_reward_awarded_keys"   // 幂等键集合
        static let passedLexemes = "pt_reward_passed_lexemes"
    }

    /// 每次首通发放的分数。规则版本由配置下发，数额随版本固定。
    static let pointsPerFirstPass = 1

    @Published private(set) var total: Int = UserDefaults.standard.integer(forKey: Key.total)

    private init() {}

    /// 功能是否启用：配置下发了规则版本才启用（字典 §13：功能上线才启用）
    var isEnabled: Bool { ResearchConfig.shared.rewardRuleVersion != nil }

    private var awardedKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Key.awardedKeys) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Key.awardedKeys) }
    }
    private var passedLexemes: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Key.passedLexemes) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Key.passedLexemes) }
    }

    /// 结算一次练习。返回实际发放的分数（0 表示未发）。
    ///
    /// - 只有**有效评分通过**才发（字典 §13）。技术失败没有成绩，自然不发。
    /// - **每个词首次说对**才发；同词重练不再发，否则挑最容易的词刷分。
    /// - 幂等键 = attemptID + 规则版本：重复结算同一次尝试不会重复发奖。
    @discardableResult
    func settle(attemptID: UUID, lexemeID: String, passed: Bool) -> Int {
        guard isEnabled, passed else { return 0 }
        guard let rule = ResearchConfig.shared.rewardRuleVersion else { return 0 }

        let key = "\(attemptID.uuidString)|\(rule)"
        var keys = awardedKeys
        guard !keys.contains(key) else { return 0 }
        var passedSet = passedLexemes
        guard !passedSet.contains(lexemeID) else { return 0 }   // 该词已首通过

        keys.insert(key); awardedKeys = keys
        passedSet.insert(lexemeID); passedLexemes = passedSet
        let delta = Self.pointsPerFirstPass
        total += delta
        UserDefaults.standard.set(total, forKey: Key.total)

        // 研究镜像：只对已纳入研究者生成，**用同一幂等键**
        RewardEventLog.shared.record(attemptID: attemptID, rewardRuleVersion: rule,
                                     pointsDelta: delta)
        return delta
    }

    /// 仅供测试与本地数据清理
    func reset() {
        let d = UserDefaults.standard
        [Key.total, Key.awardedKeys, Key.passedLexemes].forEach { d.removeObject(forKey: $0) }
        total = 0
    }
}

/// 研究镜像（字典 §13 research_reward_events）。
/// 未参加研究者不生成镜像，但业务积分照发。
@MainActor
final class RewardEventLog {
    static let shared = RewardEventLog()
    private(set) var pending: [Record] = []
    private init() {}

    nonisolated struct Record: Codable, Equatable {
        let rewardEventID: UUID
        let attemptID: UUID
        let rewardRuleVersion: String
        let pointsDelta: Int
        let awardedAt: Date
    }

    func record(attemptID: UUID, rewardRuleVersion: String, pointsDelta: Int) {
        guard ResearchEventLog.shared.isCollecting else { return }
        pending.append(Record(rewardEventID: UUID(), attemptID: attemptID,
                              rewardRuleVersion: rewardRuleVersion,
                              pointsDelta: pointsDelta, awardedAt: Date()))
    }

    func clearPendingOnWithdrawal() { pending.removeAll() }
    func remove(_ ids: Set<UUID>) { pending.removeAll { ids.contains($0.rewardEventID) } }
}
