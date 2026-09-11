import Foundation

/// 上行同步数据传输对象（DTO）。与 Core Data 实体解耦，时间统一 ISO8601。
/// 后端 FastAPI 入库 PostgreSQL，仅做数据层，不做音频处理。

private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

/// `/student/register` 的响应。后端已不再下发任何实验分组字段；
/// 保留空结构体只为让调用方的 `try await` 有确定的返回类型。
nonisolated struct StudentRegistration: Codable {}

nonisolated struct TrainingSessionDTO: Codable {
    let id: String
    let deviceID: String
    let classCode: String?
    let role: String
    let groupAssignment: String
    let lexemeID: String
    let dtwScore: Double
    let grade: String
    let attemptNumber: Int
    let timestamp: String
    // 诊断埋点（P1-3）：用于下一轮自查"卡词/失败/技术问题"
    let referenceType: String?      // real | tts | ideal
    let voicedFrameCount: Int
    let qualityFlag: Bool
    let referenceSwitchedDuringAttempt: Bool
    // 研究字段（升级需求 §3.1 / §3.2）
    let phase: String?                 // pretest | training | posttest
    let wordSetID: String?             // set1 | set2 | assessment
    let presentationOrder: String?     // 历史字段；A/B 取消后恒为 nil
    let assessmentSetVersion: String?  // 仅测试词集记录有值
    // 记录语义与版本（升级需求 §6.1 / §6.2）
    let feedbackMode: String?          // 历史字段；A/B 取消后恒为 nil
    let resultStatus: String?          // valid_result | technical_retry | quality_flagged
    let failureReason: String?         // 技术失败原因；有效记录为 nil
    let schemaVersion: Int?            // 记录字段版本
    let appVersion: String?            // 产生该记录的 App 版本
}

nonisolated struct AspirationAttemptDTO: Codable {
    let id: String
    let deviceID: String
    let classCode: String?
    let role: String
    let targetWord: String
    let triggerRate: Double
    let passed: Bool
    let timestamp: String
    let phase: String?                 // 研究阶段，供按阶段筛选（升级需求 §3.1）
    let schemaVersion: Int?
    let appVersion: String?
}

nonisolated struct FreeTextRecordDTO: Codable {
    let id: String
    let deviceID: String
    let classCode: String?
    let role: String
    let originalText: String
    let tokenizedWord: String
    let pinyin: String
    let toneSequence: [Int]
    let f0Track: [Float]
    let duration: Double
    let timestamp: String
    let phase: String?                 // 研究阶段，供按阶段筛选（升级需求 §3.1）
    let schemaVersion: Int?
    let appVersion: String?
}

// MARK: - 实体 → DTO（在主线程/拥有上下文的线程调用）

extension TrainingSession {
    func toDTO() -> TrainingSessionDTO {
        TrainingSessionDTO(
            id: id.uuidString,
            deviceID: deviceID,
            classCode: classCode,
            role: role,
            groupAssignment: groupAssignment,
            lexemeID: lexemeID,
            dtwScore: dtwScore,
            grade: grade,
            attemptNumber: Int(attemptNumber),
            timestamp: iso8601.string(from: timestamp),
            referenceType: referenceType,
            voicedFrameCount: Int(voicedFrameCount),
            qualityFlag: qualityFlag,
            referenceSwitchedDuringAttempt: referenceSwitchedDuringAttempt,
            phase: phase,
            wordSetID: wordSetID,
            presentationOrder: presentationOrder,
            assessmentSetVersion: assessmentSetVersion,
            feedbackMode: feedbackMode,
            resultStatus: resultStatus,
            failureReason: failureReason,
            schemaVersion: Int(schemaVersion),
            appVersion: appVersion
        )
    }
}

extension AspirationAttempt {
    func toDTO() -> AspirationAttemptDTO {
        AspirationAttemptDTO(
            id: id.uuidString,
            deviceID: deviceID,
            classCode: classCode,
            role: role,
            targetWord: targetWord,
            triggerRate: triggerRate,
            passed: passed,
            timestamp: iso8601.string(from: timestamp),
            phase: phase,
            schemaVersion: Int(schemaVersion),
            appVersion: appVersion
        )
    }
}

extension FreeTextRecord {
    func toDTO() -> FreeTextRecordDTO {
        FreeTextRecordDTO(
            id: id.uuidString,
            deviceID: deviceID,
            classCode: classCode,
            role: role,
            originalText: originalText,
            tokenizedWord: tokenizedWord,
            pinyin: pinyin,
            toneSequence: toneSequence,
            f0Track: f0Track,
            duration: duration,
            timestamp: iso8601.string(from: timestamp),
            phase: phase,
            schemaVersion: Int(schemaVersion),
            appVersion: appVersion
        )
    }
}
