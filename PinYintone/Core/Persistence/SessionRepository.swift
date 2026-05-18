import CoreData

final class SessionRepository {
    static let shared = SessionRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    func save(deviceID: String, classCode: String?, role: String,
              groupAssignment: String, lexemeID: String,
              dtwScore: Double, grade: String,
              attemptNumber: Int, timestamp: Date) {
        fatalError("TODO: 实现")
    }

    func fetchUnsynced() -> [TrainingSession] {
        fatalError("TODO: 实现")
    }

    func markSynced(_ sessions: [TrainingSession]) {
        fatalError("TODO: 实现")
    }
}
