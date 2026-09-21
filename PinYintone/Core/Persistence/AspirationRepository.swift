import CoreData

final class AspirationRepository {
    static let shared = AspirationRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    @discardableResult
    func save(deviceID: String, classCode: String?, role: String,
              targetWord: String, triggerRate: Double,
              passed: Bool, timestamp: Date,
              phase: String? = nil) -> AspirationAttempt {
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
        attempt.phase = phase
        attempt.schemaVersion = Int16(RecordSchema.version)
        attempt.appVersion = RecordSchema.appVersion
        saveContext()
        return attempt
    }

    /// 本机全部送气记录（测试与本地统计用）
    func fetchAll() -> [AspirationAttempt] {
        let req: NSFetchRequest<AspirationAttempt> = AspirationAttempt.fetchRequest()
        return (try? context.fetch(req)) ?? []
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
