import Foundation

/// 研究埋点的**唯一入口门禁**。
///
/// 字典 §1 要求端侧筛选：「仅符合条件并明确同意者写入研究库」，
/// 且「后台不得先收集所有用户的研究事件，再只在导出时过滤」。
///
/// 因此所有 `research_*` 写入都必须先问这里，而不是先写下来等服务端或导出时再筛。
/// 把判断集中在一处，是为了避免「每处埋点都记得加条件」——那个约定在本项目
/// 已被证伪过不止一次（技术失败哨兵在 export.sql 里筛了、teacher.py 里漏了；
/// 问卷接口漏了同意校验）。
///
/// 两道门要分清（需求 R04）：
/// - `shouldCollect`：能不能**产生新的**研究数据。要求此刻在采集窗口内。
/// - `canUpload`：能不能**补传已经合法产生的**数据。不看窗口——
///   窗口内产生、窗口关闭后才联网的记录照样要传，窗口关闭不清队列。
@MainActor
enum ResearchGate {

    /// 当前是否应当产生研究记录。
    ///
    /// 缺一不可：服务端已确认纳入、端侧资格为 eligible、持有研究身份、
    /// 此刻处于纳入所用配置的采集窗口内。
    /// 「已同意但尚未纳入」不算——服务端确认之前不产生研究日志。
    static func shouldCollect(now: Date = Date()) -> Bool {
        shouldCollect(state: ResearchStore.shared.state, now: now)
    }

    /// 纯函数版本，便于测试。
    nonisolated static func shouldCollect(state: ResearchState, now: Date) -> Bool {
        guard state.participation == .enrolled else { return false }
        guard state.eligibilityOutcome == .eligible else { return false }
        guard state.hasIdentity else { return false }
        guard let window = state.window else { return false }   // 窗口未知则不采集，不猜测
        return window.contains(now)
    }

    /// 是否可以上传已产生的研究数据。退出后一律不行（由退出指令先行）。
    nonisolated static func canUpload(state: ResearchState) -> Bool {
        state.participation == .enrolled && state.hasIdentity
            && state.pendingWithdrawal == nil
    }

    /// 采集窗口（字典 §3 `collection_start_at` / `collection_end_at`）。
    ///
    /// 由配置显式给出起止时间，**左闭右开**：起点纳入、终点排除。
    /// 长度不再固定为 14 天（需求 R04），由研究者与导师确定。
    nonisolated struct CollectionWindow: Equatable {
        let start: Date
        let end: Date
        func contains(_ t: Date) -> Bool { t >= start && t < end }
    }
}
