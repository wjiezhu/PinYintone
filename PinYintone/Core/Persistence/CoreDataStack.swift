import CoreData

final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    var context: NSManagedObjectContext { container.viewContext }

    private init() {
        container = NSPersistentContainer(name: "PinYintone")
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Core Data 加载失败: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
