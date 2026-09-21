import CoreData

final class SessionRepository {
    static let shared = SessionRepository()
    private let context = CoreDataStack.shared.context

    private init() {}

    @discardableResult
    func save(deviceID: String, classCode: String?, role: String,
              groupAssignment: String, lexemeID: String,
              dtwScore: Double, grade: String,
              attemptNumber: Int, timestamp: Date,
              referenceType: String? = nil,
              voicedFrameCount: Int = 0,
              qualityFlag: Bool = false,
              referenceSwitchedDuringAttempt: Bool = false,
              phase: String? = nil,
              wordSetID: String? = nil,
              presentationOrder: String? = nil,
              assessmentSetVersion: String? = nil,
              feedbackMode: String? = nil,
              resultStatus: ResultStatus = .validResult,
              failureReason: FailureReason? = nil) -> TrainingSession {
        let session = TrainingSession(context: context)
        session.id = UUID()
        session.deviceID = deviceID
        session.classCode = classCode
        session.role = role
        session.groupAssignment = groupAssignment
        session.lexemeID = lexemeID
        session.dtwScore = dtwScore
        session.grade = grade
        session.attemptNumber = Int32(attemptNumber)
        session.synced = false
        session.timestamp = timestamp
        // 诊断埋点（P1-3）
        session.referenceType = referenceType
        session.voicedFrameCount = Int32(voicedFrameCount)
        session.qualityFlag = qualityFlag
        session.referenceSwitchedDuringAttempt = referenceSwitchedDuringAttempt
        // 研究字段（升级需求 §3.1 / §3.2）
        session.phase = phase
        session.wordSetID = wordSetID
        session.presentationOrder = presentationOrder
        session.assessmentSetVersion = assessmentSetVersion
        // 记录语义与版本（升级需求 §6.1 / §6.2）
        session.feedbackMode = feedbackMode
        session.resultStatus = resultStatus.rawValue
        session.failureReason = failureReason?.rawValue
        session.schemaVersion = Int16(RecordSchema.version)
        session.appVersion = RecordSchema.appVersion
        saveContext()
        return session
    }

    /// 技术性失败记录（升级需求 §6.1）。
    ///
    /// 只记"这次录音因技术原因没成"，**不生成发音等级**：`dtwScore` / `grade`
    /// 写 `RecordSentinel` 的占位值，`resultStatus = technical_retry`。
    /// 取数时必须按 `resultStatus` 筛掉，不得进入发音成绩统计（CLAUDE.md 禁令 9）。
    ///
    /// 不调用 `ToneAttemptStore.increment`：没录上不算"练过这个词"，
    /// 否则反复启动失败就能把后测解锁条件刷开。
    @discardableResult
    func saveTechnicalRetry(deviceID: String, classCode: String?, role: String,
                            lexemeID: String, attemptNumber: Int, timestamp: Date,
                            phase: String?, wordSetID: String?,
                            assessmentSetVersion: String?,
                            voicedFrameCount: Int,
                            reason: FailureReason) -> TrainingSession {
        save(deviceID: deviceID, classCode: classCode, role: role,
             groupAssignment: "n/a", lexemeID: lexemeID,
             dtwScore: RecordSentinel.noScore, grade: RecordSentinel.noGrade,
             attemptNumber: attemptNumber, timestamp: timestamp,
             voicedFrameCount: voicedFrameCount,
             phase: phase, wordSetID: wordSetID,
             assessmentSetVersion: assessmentSetVersion,
             feedbackMode: nil,
             resultStatus: .technicalRetry,
             failureReason: reason)
    }

    /// 学习记录页用：按时间倒序取本机记录。
    ///
    /// **排除技术失败**（`resultStatus = technical_retry`）：那些记录的
    /// `dtwScore` 是 -1 哨兵、`grade` 是 "n/a"，本就不是发音成绩，
    /// 显示出来会被读成「拿了个负分」。失败次数另行统计，不混进成绩列表。
    func fetchHistory(limit: Int = 200) -> [TrainingSession] {
        let req: NSFetchRequest<TrainingSession> = TrainingSession.fetchRequest()
        req.predicate = NSPredicate(format: "resultStatus != %@ OR resultStatus == nil",
                                    ResultStatus.technicalRetry.rawValue)
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        req.fetchLimit = limit
        return (try? context.fetch(req)) ?? []
    }

    /// 技术失败的次数。单独呈现——它反映的是录音是否顺利，不是发音水平。
    func technicalRetryCount() -> Int {
        let req: NSFetchRequest<TrainingSession> = TrainingSession.fetchRequest()
        req.predicate = NSPredicate(format: "resultStatus == %@",
                                    ResultStatus.technicalRetry.rawValue)
        return (try? context.count(for: req)) ?? 0
    }

    func fetchUnsynced() -> [TrainingSession] {
        let req = TrainingSession.fetchRequest()
        req.predicate = NSPredicate(format: "synced == NO")
        req.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    func markSynced(_ sessions: [TrainingSession]) {
        sessions.forEach { $0.synced = true }
        saveContext()
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
