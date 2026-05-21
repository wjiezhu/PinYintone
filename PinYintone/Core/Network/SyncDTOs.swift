import Foundation

/// 上行同步数据传输对象（DTO）。与 Core Data 实体解耦，时间统一 ISO8601。
/// 后端 FastAPI 入库 PostgreSQL，仅做数据层，不做音频处理。

private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
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
            timestamp: iso8601.string(from: timestamp)
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
