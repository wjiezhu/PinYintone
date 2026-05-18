import CoreData

final class FreeTextRepository {
    static let shared = FreeTextRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    func save(word: String, f0Track: [Float], timestamp: Date) {
        fatalError("TODO: 实现")
    }

    func fetchUnsynced() -> [FreeTextRecord] {
        fatalError("TODO: 实现")
    }

    func markSynced(_ records: [FreeTextRecord]) {
        fatalError("TODO: 实现")
    }
}
