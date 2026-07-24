import CoreData
import Foundation

/// 本机数据清除：删除账号时抹除所有本地训练记录与练习进度。
///
/// App Store 审核指南 5.1.1(v)：提供账号注册的 App 必须能真正删除账号数据，
/// 仅"退出登录"不满足要求。服务端删除由 `APIClient.deleteAccount` 负责，
/// 本类负责机上残留（Core Data 三张表 + UserDefaults 里的游标/计数）。
enum LocalDataPurger {

    /// 需一并清除的本地进度键（与 CorpusLoader / ToneTrainingViewModel 对应）
    private static let progressKeys = [
        "pt_corpus_cursor_tone",
        "pt_corpus_cursor_aspiration",
        "pt_tone_attempts",
    ]

    static func purgeAll() {
        purgeCoreData()
        progressKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func purgeCoreData() {
        let context = CoreDataStack.shared.context
        for entity in ["TrainingSession", "AspirationAttempt", "FreeTextRecord"] {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let delete = NSBatchDeleteRequest(fetchRequest: fetch)
            delete.resultType = .resultTypeObjectIDs
            guard let result = try? context.execute(delete) as? NSBatchDeleteResult,
                  let ids = result.result as? [NSManagedObjectID], !ids.isEmpty else { continue }
            // 批量删除绕过上下文，需手动合并变更，否则内存中仍持有已删对象
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: ids], into: [context])
        }
        if context.hasChanges { try? context.save() }
    }
}
