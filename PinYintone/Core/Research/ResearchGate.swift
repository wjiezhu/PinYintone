import Foundation

/// 研究埋点的**唯一入口门禁**。
///
/// 字典 §1 要求端侧筛选：「仅符合条件并明确同意者写入研究库」，
/// 且「后台不得先收集所有用户的研究事件，再只在导出时过滤」。
///
/// 因此所有 `research_*` 写入都必须先问 `shouldCollect`，
/// 而不是先写下来等服务端或导出时再筛。把判断集中在这里，
/// 是为了避免「每处埋点都记得加条件」——那个约定在本项目已被证伪过一次
/// （技术失败哨兵值在 export.sql 里筛了、在 teacher.py 里漏了）。
@MainActor
enum ResearchGate {

    /// 当前是否应当产生研究记录。
    ///
    /// 四个条件缺一不可：持有有效同意、资格判定为 eligible、
    /// 处于采集窗口内、且不是测试账户被排除的情形。
    /// - Parameters:
    ///   - eligibility: 端侧资格判定结果
    ///   - now: 判定时刻（便于测试注入）
    ///   - window: 采集窗口，左闭右开；统一 14 天，**非每人 14 天**
    static func shouldCollect(eligibility: ResearchEligibility.Outcome,
                              now: Date = Date(),
                              window: CollectionWindow?) -> Bool {
        guard ResearchConsent.shared.allowsResearchCollection else { return false }
        guard eligibility == .eligible else { return false }
        guard let window else { return false }   // 窗口未配置则不采集，不猜测
        return window.contains(now)
    }

    /// 采集窗口（字典 §3 `collection_start_at` / `collection_end_at`）。
    ///
    /// 统一窗口、左闭右开。`collection_start_at` 是新版在 App Store
    /// **实际公开可用**的时点，须上线后核实，不得填预计日期。
    struct CollectionWindow {
        let start: Date
        let end: Date
        func contains(_ t: Date) -> Bool { t >= start && t < end }
    }
}
