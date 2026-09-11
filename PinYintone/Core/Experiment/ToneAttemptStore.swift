import Foundation

/// 关卡 2 按词累计尝试数。换词不归零，可还原练习轮次。
///
/// 从 `ToneTrainingViewModel` 抽出为共享存储：阶段推进（后测解锁条件）
/// 与训练页都要读它，两处各存一份会不一致。
/// 存储键沿用旧值，历史数据直接继承。
enum ToneAttemptStore {
    private static let key = "pt_tone_attempts"

    static var all: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    static func attempts(for lexemeID: String) -> Int { all[lexemeID] ?? 0 }

    /// 自增并返回本次的尝试序号（1-based）
    @discardableResult
    static func increment(_ lexemeID: String) -> Int {
        var dict = all
        let next = (dict[lexemeID] ?? 0) + 1
        dict[lexemeID] = next
        UserDefaults.standard.set(dict, forKey: key)
        return next
    }

    /// 给定词条是否都至少练过一次
    static func allAttempted(_ lexemeIDs: [String]) -> Bool {
        let dict = all
        return !lexemeIDs.isEmpty && lexemeIDs.allSatisfy { (dict[$0] ?? 0) > 0 }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
