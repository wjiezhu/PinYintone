import Foundation

/// 操作事件（字段字典 §8）。事件名是**白名单**，不得随意扩展：
/// 扩展枚举必须同步递增字典版本，否则服务端按冻结版本校验会拒收。
nonisolated enum ResearchEventName: String, Codable, CaseIterable {
    case taskOpened = "task_opened"
    case modelAudioStarted = "model_audio_started"
    case learnerAudioStarted = "learner_audio_started"
    case feedbackDisplayed = "feedback_displayed"
    case feedbackModeChanged = "feedback_mode_changed"
    case historyOpened = "history_opened"
    case operationError = "operation_error"
    case crashReportReceived = "crash_report_received"
    /// 现场实测（2026-10-28）：流程开始、某一段走完、流程结束（完成或中途离开）
    case fieldSessionStarted = "field_session_started"
    case fieldStepCompleted = "field_step_completed"
    case fieldSessionEnded = "field_session_ended"

    /// 是否必须携带 attempt_id（字典 §8 表格）
    var requiresAttempt: Bool {
        switch self {
        case .learnerAudioStarted, .feedbackDisplayed, .feedbackModeChanged: return true
        default: return false
        }
    }
}

/// 固定错误码（字典 §8）。未经明确捕获的退出**不得**编码为 crash。
nonisolated enum ResearchErrorCode: String, Codable {
    case permissionDenied = "permission_denied"
    case noSignal = "no_signal"
    case signalUnusable = "signal_unusable"
    case networkUnavailable = "network_unavailable"
    case timeout
    case analysisEngineError = "analysis_engine_error"
    case playbackError = "playback_error"
    case renderError = "render_error"
    case adviceServiceError = "advice_service_error"
    case unknown
}

nonisolated enum ResearchErrorStage: String, Codable {
    case recording, analysis, playback, feedback, advice, other
}

/// 反馈呈现方式。字典用 static_color / pitch_curve，与 App 内部 `FeedbackStyle`
/// 的 staticColor / dynamicF0 命名不同——**转换只走这里**，理由同轻声编码：
/// 原样上报不会报错，只有取数时才发现值对不上（见 `ResearchToneCoding`）。
nonisolated enum ResearchFeedbackMode: String, Codable {
    case staticColor = "static_color"
    case pitchCurve = "pitch_curve"

    init(_ style: FeedbackStyle) {
        switch style {
        case .staticColor: self = .staticColor
        case .dynamicF0:   self = .pitchCurve
        }
    }
}

/// 一条待上报的操作事件。
nonisolated struct ResearchEvent: Codable, Equatable {
    /// 主键，**离线上传幂等键**：同一事件重传复用同一 id，服务端靠唯一约束去重
    let eventID: UUID
    let sessionID: UUID
    let attemptID: UUID?
    let lexemeVersionID: String?
    let name: ResearchEventName
    let occurredAt: Date
    /// 同一会话内单调经过时长，非负；用单调时钟测，不用手机墙钟差值
    let sessionElapsedMs: Int64?
    let uiLanguage: String
    let payload: [String: String]

    /// 上报时的字段名以服务端 `ResearchEventDTO` 为准。
    ///
    /// ⚠ 历史缺陷：本类型曾按属性名原样编码，事件名发成了 `name`，
    /// 而服务端要的是 `eventName`——**真实 App 发出的每一条事件都被 422 拒收**。
    /// 接口验证脚本自己拼的请求体字段是对的，所以脚本全绿、App 全丢。
    /// `ResearchWireFormatTests` 现在逐字段对照两端。
    enum CodingKeys: String, CodingKey {
        case eventID, sessionID, attemptID, lexemeVersionID
        case name = "eventName"
        case occurredAt, sessionElapsedMs, uiLanguage, payload
    }

    enum ValidationError: Error, Equatable {
        case missingAttemptID(ResearchEventName)
        case negativeElapsed(Int64)
        case payloadKeyNotAllowed(String)
    }

    /// 按字典 §8 校验。**构造即校验**，不允许先落库再补检。
    func validate() throws {
        if name.requiresAttempt && attemptID == nil {
            throw ValidationError.missingAttemptID(name)
        }
        if let e = sessionElapsedMs, e < 0 {
            throw ValidationError.negativeElapsed(e)
        }
        let allowed = Self.allowedPayloadKeys(for: name)
        for key in payload.keys where !allowed.contains(key) {
            throw ValidationError.payloadKeyNotAllowed(key)
        }
    }

    /// 各事件允许的 payload 字段（字典 §8）。表中无参数的事件为空对象。
    static func allowedPayloadKeys(for name: ResearchEventName) -> Set<String> {
        switch name {
        case .taskOpened:          return ["task_type"]
        case .feedbackDisplayed:   return ["mode"]
        case .feedbackModeChanged: return ["from_mode", "to_mode"]
        case .operationError:      return ["stage", "error_code"]
        case .crashReportReceived: return ["crash_occurred_at"]
        case .modelAudioStarted, .learnerAudioStarted, .historyOpened:
            return []
        case .fieldSessionStarted: return ["field_session_id", "protocol_version"]
        case .fieldStepCompleted:  return ["field_session_id", "step"]
        case .fieldSessionEnded:   return ["field_session_id", "outcome", "last_step"]
        }
    }
}
