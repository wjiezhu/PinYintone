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
    /// - 3：**取消 A/B 分组**。`staticColor` / `dynamicF0` 改为学习者在设置里
    ///      随时可切的显示偏好，两者通关标准一致。
    ///      `feedbackMode` 记录该条记录当时用的是哪种显示（裸测阶段为 nil）——
    ///      **因为是自选的，禁止拿它做组间比较**（自选择偏差，不是随机分配）。
    ///      `presentationOrder` 不再写入（恒为 nil），`groupAssignment` 恒为 `"n/a"`。
    ///      v3 记录**不可**整体视为单一呈现条件，也不可与 v1/v2 的随机分配值混在一起分析。
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

/// 技术失败记录的占位值。
///
/// 技术性失败没有发音成绩，但 `dtwScore` / `grade` 在库里是非空列，必须写点什么。
/// **绝不能写 0**——DTW 距离越小越好，0 会被读成满分；也**绝不能写 `fail`**，
/// 那是发音判定（CLAUDE.md 禁令 9）。这里用真实分数不可能取到的值，
/// 让漏筛 `resultStatus` 的分析一眼看出异常，而不是被悄悄算进均值。
enum RecordSentinel {
    /// 真实 DTW 距离恒 ≥ 0，故 -1 不会与任何有效分撞车
    static let noScore: Double = -1
    /// 非 FeedbackGrade 的任何取值，明确表示"未生成等级"
    static let noGrade = "n/a"
}

/// 技术失败原因（升级需求 §6.1）。仅记录匿名原因，不含任何录音内容。
enum FailureReason: String, Codable {
    case insufficientVoicedFrames = "insufficient_voiced_frames"
    case permissionDenied = "permission_denied"
    case recordingInterrupted = "recording_interrupted"
    case lowSignalQuality = "low_signal_quality"
    case analysisError = "analysis_error"
}
