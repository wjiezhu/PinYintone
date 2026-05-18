import CoreData
import Foundation

@objc(TrainingSession)
public class TrainingSession: NSManagedObject {}

extension TrainingSession {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TrainingSession> {
        NSFetchRequest<TrainingSession>(entityName: "TrainingSession")
    }

    @NSManaged public var id: UUID
    @NSManaged public var deviceID: String
    @NSManaged public var classCode: String?   // nil = 游客
    @NSManaged public var role: String         // "guest" | "student"
    @NSManaged public var groupAssignment: String // "staticColor" | "dynamicF0"
    @NSManaged public var lexemeID: String
    @NSManaged public var dtwScore: Double
    @NSManaged public var grade: String        // FeedbackGrade.rawValue
    @NSManaged public var attemptNumber: Int32
    @NSManaged public var synced: Bool
    @NSManaged public var timestamp: Date
}
