import Foundation

/// 操作事件的采集入口。
///
/// 硬约束：
/// 1. **门禁在写入前**——未纳入/不合资格/窗口外一律不产生研究事件，
///    而不是先收集再在导出时过滤（字典 §1 明确禁止后者）。
/// 2. **事件即校验**——`ResearchEvent.validate()` 不通过就不入队，
///    避免脏事件进了队列再在上报时被服务端拒收、变成静默丢失。
/// 3. **幂等键随事件生成**——重传复用同一 `eventID`，不在上报时另生成。
/// 4. **队列落盘、按账号隔离**——此前只在内存里，App 被杀即丢。
@MainActor
final class ResearchEventLog {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = ResearchEventLog()

    private static let queueName = "events"

    /// 待上报队列。退出研究时必须清空（字典 §5：端侧立即停止并清除待上传队列）。
    private(set) var pending: [ResearchEvent] = []

    private init() {}

    /// 当前是否在采集。
    var isCollecting: Bool { ResearchGate.shouldCollect() }

    /// 换账号后从该账号的存储域重新加载
    func reload() {
        pending = ResearchStore.shared.loadQueue(Self.queueName)
    }

    /// 记录一条事件。返回是否真的入队（未采集或校验失败为 false）。
    @discardableResult
    func log(_ name: ResearchEventName,
             attemptID: UUID? = nil,
             lexemeVersionID: String? = nil,
             payload: [String: String] = [:],
             now: Date = Date()) -> Bool {
        guard ResearchGate.shouldCollect(now: now) else { return false }
        let event = ResearchEvent(
            eventID: UUID(),
            sessionID: ResearchSession.shared.sessionID,
            attemptID: attemptID,
            lexemeVersionID: lexemeVersionID,
            name: name,
            occurredAt: now,
            sessionElapsedMs: ResearchSession.shared.elapsedMs,
            // 用户在 App 内选择并实际看到的界面语言（zh/en/fr/ar），
            // 不是系统区域。此前取的是 Locale.preferredLanguages，
            // 会报出 fr-MA、en-US 这类与界面无关的值。
            uiLanguage: LocalizationManager.shared.language,
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
        persist()
        return true
    }

    /// 退出研究：立即清空待上传队列（字典 §5）
    func clearPendingOnWithdrawal() {
        pending.removeAll()
        persist()
    }

    /// 上报成功（或被服务端明确拒收）后移除
    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pending.removeAll { ids.contains($0.eventID) }
        persist()
    }

    private func persist() {
        ResearchStore.shared.saveQueue(Self.queueName, pending)
    }
}
