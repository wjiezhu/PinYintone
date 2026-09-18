import Foundation

/// 前台使用会话编号（字典 §7 `session_id`）。
///
/// 操作定义：**冷启动，或退到后台超过 30 分钟**，即创建新编号。
/// 字典明确这是操作定义，**不是真实学习课次**，统计时不得当作一节课解读。
///
/// `session_elapsed_ms` 用单调时钟测量：手机墙钟会被用户改动或被系统校时，
/// 用它做差值会出现负数或跳变，而字典要求该值非负且单调。
@MainActor
final class ResearchSession {
    static let shared = ResearchSession()

    /// 后台超过此时长即视为新会话
    static let backgroundThreshold: TimeInterval = 30 * 60

    private(set) var sessionID = UUID()
    private var startedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var backgroundedAtUptime: TimeInterval?

    private init() {}

    /// 自本会话开始的单调经过毫秒数
    var elapsedMs: Int64 {
        let d = ProcessInfo.processInfo.systemUptime - startedAtUptime
        return Int64(max(0, d * 1000))
    }

    func didEnterBackground(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        backgroundedAtUptime = now
    }

    /// 回到前台。超过阈值则轮换会话编号并返回 true。
    @discardableResult
    func willEnterForeground(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        defer { backgroundedAtUptime = nil }
        guard let bg = backgroundedAtUptime else { return false }
        guard now - bg > Self.backgroundThreshold else { return false }
        rotate(now: now)
        return true
    }

    /// 冷启动或跨过阈值时轮换
    func rotate(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        sessionID = UUID()
        startedAtUptime = now
    }
}
