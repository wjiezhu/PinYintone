import CoreData

final class SessionRepository {
    static let shared = SessionRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    @discardableResult
    func save(deviceID: String, classCode: String?, role: String,
              groupAssignment: String, lexemeID: String,
              dtwScore: Double, grade: String,
              attemptNumber: Int, timestamp: Date,
              referenceType: String? = nil,
              voicedFrameCount: Int = 0,
              qualityFlag: Bool = false,
              referenceSwitchedDuringAttempt: Bool = false,
              phase: String? = nil,
              wordSetID: String? = nil,
              presentationOrder: String? = nil,
              assessmentSetVersion: String? = nil,
              feedbackMode: String? = nil,
              resultStatus: ResultStatus = .validResult,
              failureReason: FailureReason? = nil) -> TrainingSession {
        let session = TrainingSession(context: context)
        session.id = UUID()
        session.deviceID = deviceID
        session.classCode = classCode
        session.role = role
        session.groupAssignment = groupAssignment
        session.lexemeID = lexemeID
        session.dtwScore = dtwScore
        session.grade = grade
        session.attemptNumber = Int32(attemptNumber)
        session.synced = false
        session.timestamp = timestamp
        // 诊断埋点（P1-3）
        session.referenceType = referenceType
        session.voicedFrameCount = Int32(voicedFrameCount)
        session.qualityFlag = qualityFlag
        session.referenceSwitchedDuringAttempt = referenceSwitchedDuringAttempt
        // 研究字段（升级需求 §3.1 / §3.2）
        session.phase = phase
        session.wordSetID = wordSetID
        session.presentationOrder = presentationOrder
        session.assessmentSetVersion = assessmentSetVersion
        // 记录语义与版本（升级需求 §6.1 / §6.2）
        session.feedbackMode = feedbackMode
        session.resultStatus = resultStatus.rawValue
        session.failureReason = failureReason?.rawValue
        session.schemaVersion = Int16(RecordSchema.version)
        session.appVersion = RecordSchema.appVersion
        saveContext()
        return session
    }

    func fetchUnsynced() -> [TrainingSession] {
        let req = TrainingSession.fetchRequest()
        req.predicate = NSPredicate(format: "synced == NO")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    func markSynced(_ sessions: [TrainingSession]) {
        sessions.forEach { $0.synced = true }
        saveContext()
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
