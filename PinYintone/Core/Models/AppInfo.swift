import Foundation

/// App 版本信息。随每条记录上报（P1-5#4）：万一实验期被迫发版，
/// 分析时可据此区分数据来源，避免版本不一致污染数据。
enum AppInfo {
    /// 形如 "1.0 (16)"：营销版本号 + 构建号
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
