import Foundation

/// 记录版本与结果状态（升级需求 §6.1 / §6.2）。
///
/// 档案要求 `appVersion` 和 `schemaVersion` 随每条记录上报，
/// 用于区分算法或字段升级前后的数据。
enum RecordSchema {
    /// 记录字段版本。**字段增删或语义变更时必须 +1**，并同步更新数据字典。
    ///
    /// - 1：受试内 A/B 上线前的历史记录（旧客户端不上报本字段，后端读到 nil 视为 1）
    /// - 2：改用 `phase` / `wordSetID` / `presentationOrder` / `assessmentSetVersion`，
    ///      并新增 `feedbackMode` / `resultStatus` / `failureReason`
    /// - 3：**取消 A/B 分组**。训练阶段唯一呈现方式 = 动态 F0 可视化，
    ///      `feedbackMode` / `presentationOrder` 不再写入（恒为 nil），
    ///      `groupAssignment` 恒为 `"n/a"`。据此可把 v3 记录整体视为"动态曲线条件"。
    static let version = 3

    /// 形如 "1.2 (9)"：短版本号 + 构建号，便于按构建定位数据
    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }()
}

/// 一条记录的结果性质（升级需求 §6.1）。
///
/// 技术失败不得伪装成 `fail`：录音质量不达标只提示重录，
/// 不生成发音等级，也不进入论文主分析。
enum ResultStatus: String, Codable {
    /// 完成有效 F0 分析并生成评分，可进入主分析
    case validResult = "valid_result"
    /// 有声帧不足 / 权限失败 / 录音中断 / 信号质量不足 / 分析异常；不进入成绩统计
    case technicalRetry = "technical_retry"
    /// 生成了结果但超过质量阈值或参照异常；保留记录并在导出中显式标记
    case qualityFlagged = "quality_flagged"
}

/// 技术失败原因（升级需求 §6.1）。仅记录匿名原因，不含任何录音内容。
enum FailureReason: String, Codable {
    case insufficientVoicedFrames = "insufficient_voiced_frames"
    case permissionDenied = "permission_denied"
    case recordingInterrupted = "recording_interrupted"
    case lowSignalQuality = "low_signal_quality"
    case analysisError = "analysis_error"
}
