import Foundation

/// 上行同步数据传输对象（DTO）。与 Core Data 实体解耦，时间统一 ISO8601。
/// 后端 FastAPI 入库 PostgreSQL，仅做数据层，不做音频处理。

private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    // 显式锁 UTC：摩洛哥与中国有时差，本地时区会让"第几周/练习间隔"算错（P1-5#3）。
    // ISO8601DateFormatter 默认已是 UTC，这里显式声明以防未来改动。
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

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
    let phase: String?              // pretest | training | posttest
    let appVersion: String?         // 如 "1.0 (16)"
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
            timestamp: iso8601.string(from: timestamp)
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
            timestamp: iso8601.string(from: timestamp)
        )
    }
}
