import Foundation

/// 操作事件的采集入口。
///
/// 三条硬约束：
/// 1. **门禁在写入前**——未同意/不合资格/窗口外一律不产生研究事件，
///    而不是先收集再在导出时过滤（需求 §2、字典 §1 明确禁止后者）。
/// 2. **事件即校验**——`ResearchEvent.validate()` 不通过就不入队，
///    避免脏事件进了队列再在上报时被服务端拒收、变成静默丢失。
/// 3. **幂等键随事件生成**——重传复用同一 `eventID`，不在上报时另生成。
@MainActor
final class ResearchEventLog {
    static let shared = ResearchEventLog()

    /// 待上报队列。撤回同意时必须清空（字典 §5：端侧立即停止并清除待上传队列）。
    private(set) var pending: [ResearchEvent] = []

    /// 采集窗口，上线核实后注入；未配置则 `ResearchGate` 不采集
    var window: ResearchGate.CollectionWindow?
    /// 端侧资格判定结果
    var eligibility: ResearchEligibility.Outcome = .pending

    private init() {}

    var isCollecting: Bool {
        ResearchGate.shouldCollect(eligibility: eligibility, window: window)
    }

    /// 记录一条事件。返回是否真的入队（未采集或校验失败为 false）。
    @discardableResult
    func log(_ name: ResearchEventName,
             attemptID: UUID? = nil,
             lexemeVersionID: String? = nil,
             payload: [String: String] = [:],
             now: Date = Date()) -> Bool {
        guard isCollecting else { return false }
        let event = ResearchEvent(
            eventID: UUID(),
            sessionID: ResearchSession.shared.sessionID,
            attemptID: attemptID,
            lexemeVersionID: lexemeVersionID,
            name: name,
            occurredAt: now,
            sessionElapsedMs: ResearchSession.shared.elapsedMs,
            uiLanguage: Locale.preferredLanguages.first ?? "und",
            payload: payload
        )
        do {
            try event.validate()
        } catch {
            #if DEBUG
            print("[ResearchEventLog] 事件校验失败，未入队：\(error)")
            #endif
            return false
        }
        pending.append(event)
        return true
    }

    /// 撤回同意：立即清空待上传队列（字典 §5）
    func clearPendingOnWithdrawal() { pending.removeAll() }

    /// 上报成功后移除
    func remove(_ ids: Set<UUID>) { pending.removeAll { ids.contains($0.eventID) } }
}
