import CoreData
import Foundation

@objc(FreeTextRecord)
public class FreeTextRecord: NSManagedObject {}

extension FreeTextRecord {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FreeTextRecord> {
        NSFetchRequest<FreeTextRecord>(entityName: "FreeTextRecord")
    }

    @NSManaged public var id: UUID
    @NSManaged public var deviceID: String
    @NSManaged public var classCode: String?
    @NSManaged public var role: String
    @NSManaged public var originalText: String
    @NSManaged public var tokenizedWord: String
    @NSManaged public var pinyin: String
    // toneSequence / f0Track 在 xcdatamodeld 中设为 Binary Data
    @NSManaged public var toneSequenceData: Data?
    @NSManaged public var f0TrackData: Data?
    @NSManaged public var duration: Double
    @NSManaged public var timestamp: Date
    @NSManaged public var synced: Bool
    /// 研究阶段（升级需求 §3.1）；关卡 3 不参与 A/B，只记录阶段供筛选
    @NSManaged public var phase: String?
    /// 记录字段版本（RecordSchema.version）
    @NSManaged public var schemaVersion: Int16
    /// 产生该记录的 App 版本，形如 "1.2 (9)"
    @NSManaged public var appVersion: String?
}

extension FreeTextRecord {
    var toneSequence: [Int] {
        get {
            guard let data = toneSequenceData else { return [] }
            return (try? JSONDecoder().decode([Int].self, from: data)) ?? []
        }
        set {
            toneSequenceData = try? JSONEncoder().encode(newValue)
        }
    }

    var f0Track: [Float] {
        get {
            guard let data = f0TrackData else { return [] }
            return (try? JSONDecoder().decode([Float].self, from: data)) ?? []
        }
        set {
            f0TrackData = try? JSONEncoder().encode(newValue)
        }
    }
}
