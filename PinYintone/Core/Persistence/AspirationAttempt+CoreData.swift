import CoreData
import Foundation

@objc(AspirationAttempt)
public class AspirationAttempt: NSManagedObject {}

extension AspirationAttempt {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AspirationAttempt> {
        NSFetchRequest<AspirationAttempt>(entityName: "AspirationAttempt")
    }

    @NSManaged public var id: UUID
    @NSManaged public var deviceID: String
    @NSManaged public var classCode: String?
    @NSManaged public var role: String
    @NSManaged public var targetWord: String
    @NSManaged public var triggerRate: Double
    @NSManaged public var passed: Bool
    @NSManaged public var synced: Bool
    @NSManaged public var timestamp: Date
    /// 研究阶段（升级需求 §3.1）；旧记录为 nil，分析时按"未知阶段"处理
    @NSManaged public var phase: String?
    /// 记录字段版本（RecordSchema.version）
    @NSManaged public var schemaVersion: Int16
    /// 产生该记录的 App 版本，形如 "1.2 (9)"
    @NSManaged public var appVersion: String?
}
