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
}
