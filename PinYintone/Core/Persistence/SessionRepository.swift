import CoreData

final class SessionRepository {
    static let shared = SessionRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    @discardableResult
    func save(deviceID: String, classCode: String?, role: String,
              groupAssignment: String, lexemeID: String,
              dtwScore: Double, grade: String,
              attemptNumber: Int, timestamp: Date) -> TrainingSession {
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
