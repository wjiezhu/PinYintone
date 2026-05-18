import CoreData

final class AspirationRepository {
    static let shared = AspirationRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    func save(deviceID: String, classCode: String?, role: String,
              targetWord: String, triggerRate: Double,
              passed: Bool, timestamp: Date) {
        fatalError("TODO: 实现")
    }

    func fetchUnsynced() -> [AspirationAttempt] {
        fatalError("TODO: 实现")
    }

    func markSynced(_ attempts: [AspirationAttempt]) {
        fatalError("TODO: 实现")
    }
}
