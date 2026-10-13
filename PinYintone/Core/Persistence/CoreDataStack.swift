import CoreData

final class CoreDataStack {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    var context: NSManagedObjectContext { container.viewContext }

    private init() {
        container = NSPersistentContainer(name: "PinYintone")

        // 显式开启轻量迁移：新增的诊断字段（P1-3）均为可选/带默认值，
        // 旧版本安装升级后可直接推断映射，无需手写迁移。
        container.persistentStoreDescriptions.forEach {
            $0.shouldMigrateStoreAutomatically = true
            $0.shouldInferMappingModelAutomatically = true
        }
        #if DEBUG
        // 单元测试用内存库：测试里走练习流程会落练习记录，不能留在 App 的正式本机库里——
        // 留下来的未同步记录，下次正常启动这个 App 时会被自动同步传到后端。
        if TestHost.isRunningUnitTests {
            container.persistentStoreDescriptions.forEach {
                $0.url = URL(fileURLWithPath: "/dev/null")
            }
        }
        #endif

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }

        // 迁移失败不再直接 fatalError：被试正在实验期，启动即崩溃比丢少量
        // 未同步记录更严重。重建 store 让 App 仍可用（已同步数据在后端不受影响）。
        if let loadError {
            #if DEBUG
            print("[CoreData] 加载失败，重建 store: \(loadError)")
            #endif
            if let url = container.persistentStoreDescriptions.first?.url {
                try? container.persistentStoreCoordinator.destroyPersistentStore(
                    at: url, ofType: NSSQLiteStoreType, options: nil)
            }
            container.loadPersistentStores { _, error in
                if let error {
                    #if DEBUG
                    print("[CoreData] 重建仍失败: \(error)")
                    #endif
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
