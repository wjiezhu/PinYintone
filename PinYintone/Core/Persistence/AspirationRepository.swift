import CoreData

final class AspirationRepository {
    static let shared = AspirationRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    @discardableResult
    func save(deviceID: String, classCode: String?, role: String,
              targetWord: String, triggerRate: Double,
              passed: Bool, timestamp: Date) -> AspirationAttempt {
        let attempt = AspirationAttempt(context: context)
        attempt.id = UUID()
        attempt.deviceID = deviceID
        attempt.classCode = classCode
        attempt.role = role
        attempt.targetWord = targetWord
        attempt.triggerRate = triggerRate
        attempt.passed = passed
        attempt.synced = false
        attempt.timestamp = timestamp
        saveContext()
        return attempt
    }

    func fetchUnsynced() -> [AspirationAttempt] {
        let req = AspirationAttempt.fetchRequest()
        req.predicate = NSPredicate(format: "synced == NO")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    func markSynced(_ attempts: [AspirationAttempt]) {
        attempts.forEach { $0.synced = true }
        saveContext()
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
