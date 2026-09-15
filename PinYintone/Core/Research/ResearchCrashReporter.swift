import Foundation
import MetricKit

/// 崩溃上报（字典 §8 `crash_report_received`）。
///
/// 用 MetricKit：它是系统框架（不违反「零第三方依赖」），且提供的是**系统确认的**
/// 崩溃诊断，而不是推测。
///
/// 为什么不用「启动时检查上次是否干净退出」那种标志位：字典 §8 明确
/// **「未经明确捕获的退出不能编码为 crash」**。用户强杀、系统回收内存、
/// 调试器断开都会让标志位变脏，把它们记成崩溃会直接污染 POST04 的
/// app_crashed 自报与系统错误日志的对照分析。
///
/// `crash_occurred_at` 取 NULL：`MXDiagnosticPayload` 给的是**采集时间窗**
/// （timeStampBegin/End），不是崩溃发生的确切时刻。字典要求
/// 「无确切时间不补造」，所以宁可留空。
///
/// 不上传任何堆栈或诊断正文——字典 §8：「不上传堆栈个人信息」。
@MainActor
final class ResearchCrashReporter: NSObject {
    static let shared = ResearchCrashReporter()

    private override init() { super.init() }

    func start() {
        MXMetricManager.shared.add(self)
    }

    /// 把一批崩溃诊断记为事件。返回记录条数，便于测试。
    @discardableResult
    func record(crashCount: Int) -> Int {
        guard crashCount > 0 else { return 0 }
        var logged = 0
        for _ in 0..<crashCount {
            // payload 留空：无确切崩溃时刻，不补造
            if ResearchEventLog.shared.log(.crashReportReceived) { logged += 1 }
        }
        return logged
    }
}

extension ResearchCrashReporter: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        // 性能指标与本研究无关，不采集
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let count = payloads.reduce(0) { $0 + ($1.crashDiagnostics?.count ?? 0) }
        Task { @MainActor in ResearchCrashReporter.shared.record(crashCount: count) }
    }
}
