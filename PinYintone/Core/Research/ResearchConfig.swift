import Foundation

/// 研究配置的本地缓存。
///
/// `manifestID` **由服务端下发，客户端不硬编码**：配置由研究者冻结，
/// 硬编码会在换配置时把数据归到旧配置下，而这种错误在导出时极难发现
/// （字典 §3：不同配置不能直接混算分数）。
///
/// 取不到配置时**不猜**：没有生效配置就不纳入任何人、不产生研究事件。
@MainActor
final class ResearchConfig {
    static let shared = ResearchConfig()

    private enum Key {
        static let manifest = "pt_research_manifest_config_id"
        static let start = "pt_research_window_start"
        static let end = "pt_research_window_end"
    }

    private init() {}

    var manifestID: String? { UserDefaults.standard.string(forKey: Key.manifest) }

    /// 采集窗口。统一 14 天、左闭右开，**不是每位用户各 14 天**。
    var window: ResearchGate.CollectionWindow? {
        let d = UserDefaults.standard
        guard let s = d.object(forKey: Key.start) as? Date,
              let e = d.object(forKey: Key.end) as? Date else { return nil }
        return .init(start: s, end: e)
    }

    /// 启动时刷新。失败保持现有缓存——离线不应让已纳入的用户停止采集。
    func refresh() async {
        guard let m = try? await APIClient.shared.fetchActiveManifest() else { return }
        let d = UserDefaults.standard
        d.set(m.manifestID, forKey: Key.manifest)
        d.set(m.collectionStartAt, forKey: Key.start)
        d.set(m.collectionEndAt, forKey: Key.end)
        ResearchEventLog.shared.window = .init(start: m.collectionStartAt,
                                               end: m.collectionEndAt)
        ResearchSurveyTrigger.shared.configure(threshold: m.postTriggerCount)
    }

    /// 应用已缓存的窗口到事件门禁（启动时调用，不等网络）
    func applyCachedWindow() {
        ResearchEventLog.shared.window = window
    }
}
