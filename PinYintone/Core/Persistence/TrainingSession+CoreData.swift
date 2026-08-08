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
    @NSManaged public var classCode: String?   // 学生为 nil（未绑定班级池）
    @NSManaged public var role: String         // "student" | "teacher"
    @NSManaged public var groupAssignment: String // "staticColor" | "dynamicF0"
    @NSManaged public var lexemeID: String
    @NSManaged public var dtwScore: Double
    @NSManaged public var grade: String        // FeedbackGrade.rawValue
    @NSManaged public var attemptNumber: Int32
    @NSManaged public var synced: Bool
    @NSManaged public var timestamp: Date

    // MARK: - 诊断埋点（P1-3）
    // 均为可选/带默认值，走 Core Data 轻量迁移，旧库可直接升级。

    /// 参照来源："real" | "tts" | "ideal"（ReferenceType.rawValue）
    @NSManaged public var referenceType: String?
    /// 本次录音的有声帧数，用于区分"没录好"与"发音错"
    @NSManaged public var voicedFrameCount: Int32
    /// 异常高分标记，分析时可剔除
    @NSManaged public var qualityFlag: Bool
    /// 录音过程中参照曲线是否被替换（P0-3 修复后应恒为 false）
    @NSManaged public var referenceSwitchedDuringAttempt: Bool

    // MARK: - 实验阶段与版本（P0-6 / P1-5）

    /// 实验阶段："pretest" | "training" | "posttest"（TrainingPhase.rawValue）
    @NSManaged public var phase: String?
    /// App 版本字符串，如 "1.0 (16)"（AppInfo.versionString）
    @NSManaged public var appVersion: String?
}
