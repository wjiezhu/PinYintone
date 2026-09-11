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
    /// 历史必填列。A/B 取消后恒写 "n/a"；旧记录可能是 "staticColor" / "dynamicF0"。
    @NSManaged public var groupAssignment: String
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

    // MARK: - 研究字段（升级需求 §3.1 / §3.2）
    // 同样为可选/带默认值，走轻量迁移；旧记录读出为 nil，分析时按"未知阶段"处理。

    /// 研究阶段："pretest" | "training" | "posttest"（TrainingPhase.rawValue）
    @NSManaged public var phase: String?
    /// 词集归属："set1" | "set2" | "assessment"（WordSet.rawValue）
    @NSManaged public var wordSetID: String?
    /// **历史列**：条件呈现顺序。A/B 取消后不再写入，恒为 nil。
    @NSManaged public var presentationOrder: String?
    /// 测试词集版本；仅测试词集记录有值，训练记录为 nil
    @NSManaged public var assessmentSetVersion: String?

    // MARK: - 记录语义与版本（升级需求 §6.1 / §6.2）

    /// 该条记录当时用的显示模式："staticColor" / "dynamicF0"；裸测阶段为 nil。
    /// `schemaVersion` >= 3 是**学习者自选**的偏好——禁止当实验条件做组间比较；
    /// < 3 的同名值是当年随机分配的条件，语义不同，不可混在一起分析。
    @NSManaged public var feedbackMode: String?
    /// 结果性质："valid_result" | "technical_retry" | "quality_flagged"（ResultStatus.rawValue）
    @NSManaged public var resultStatus: String?
    /// 技术失败原因（FailureReason.rawValue）；有效记录为 nil
    @NSManaged public var failureReason: String?
    /// 记录字段版本（RecordSchema.version）
    @NSManaged public var schemaVersion: Int16
    /// 产生该记录的 App 版本，形如 "1.2 (9)"
    @NSManaged public var appVersion: String?
}
