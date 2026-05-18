import CoreData

final class FreeTextRepository {
    static let shared = FreeTextRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    @discardableResult
    func save(deviceID: String, classCode: String?, role: String,
              originalText: String, tokenizedWord: String, pinyin: String,
              toneSequence: [Int], f0Track: [Float],
              duration: Double, timestamp: Date) -> FreeTextRecord {
        let record = FreeTextRecord(context: context)
        record.id = UUID()
        record.deviceID = deviceID
        record.classCode = classCode
        record.role = role
        record.originalText = originalText
        record.tokenizedWord = tokenizedWord
        record.pinyin = pinyin
        record.toneSequence = toneSequence   // computed var: JSON-encodes to toneSequenceData
        record.f0Track = f0Track             // computed var: JSON-encodes to f0TrackData
        record.duration = duration
        record.synced = false
        record.timestamp = timestamp
        saveContext()
        return record
    }

    func fetchUnsynced() -> [FreeTextRecord] {
        let req = FreeTextRecord.fetchRequest()
        req.predicate = NSPredicate(format: "synced == NO")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    func markSynced(_ records: [FreeTextRecord]) {
        records.forEach { $0.synced = true }
        saveContext()
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
