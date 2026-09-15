import Foundation

/// 研究事件上报通道。
///
/// 设计要点：
/// - **幂等靠 eventID**：上报失败不丢事件、不换编号，下次原样重传，
///   服务端按主键去重（字典 §8、验收场景「同一 attempt 重复上传 3 次只有 1 行」）。
/// - **成功才出队**：只有服务端确认接收的事件才从待传队列移除，
///   否则离线期间的事件会静默丢失。
/// - **撤回后不补传**：撤回同意时队列已清空；即便有残留，服务端也会按
///   最新同意状态拒收（字典 §15「离线重传也不能绕过同意状态校验」）。
@MainActor
final class ResearchUploader {
    static let shared = ResearchUploader()

    /// 单批上限。批太大时一次网络失败会拖住全部事件，也容易触发服务端体积限制。
    static let batchSize = 50

    private var isUploading = false

    private init() {}

    struct Batch: Encodable {
        let participantID: String
        let manifestID: String
        let events: [ResearchEvent]
    }

    struct AttemptBatch: Encodable {
        let participantID: String
        let manifestID: String
        let attempts: [ResearchAttemptRecord]
    }

    /// 用本机研究身份上报。未纳入研究则什么也不做——
    /// 事件本就不该产生（`ResearchEventLog` 的门禁在写入前），
    /// 这里再挡一次是为了万一队列里有残留也不会误发。
    @discardableResult
    func flush() async -> Int {
        let id = ResearchIdentity.shared
        guard let pid = id.participantID, let mid = id.manifestID else { return 0 }
        return await flush(participantID: pid, manifestID: mid)
    }

    /// 尝试上报待传事件。返回成功上报的条数。
    @discardableResult
    func flush(participantID: String, manifestID: String) async -> Int {
        guard !isUploading else { return 0 }          // 避免并发重复上传
        isUploading = true
        defer { isUploading = false }

        var uploaded = 0
        // 先传尝试再传事件：事件带 attempt_id 外键，顺序反了会因外键缺失被拒。
        while true {
            let batch = Array(ResearchAttemptLog.shared.pending.prefix(Self.batchSize))
            guard !batch.isEmpty else { break }
            do {
                try await APIClient.shared.uploadResearchAttempts(
                    AttemptBatch(participantID: participantID,
                                 manifestID: manifestID,
                                 attempts: batch))
                ResearchAttemptLog.shared.remove(Set(batch.map(\.attemptID)))
                uploaded += batch.count
            } catch {
                break
            }
        }
        while true {
            let batch = Array(ResearchEventLog.shared.pending.prefix(Self.batchSize))
            guard !batch.isEmpty else { break }
            do {
                try await APIClient.shared.uploadResearchEvents(
                    Batch(participantID: participantID,
                          manifestID: manifestID,
                          events: batch))
                // 只移除服务端确认的这一批
                ResearchEventLog.shared.remove(Set(batch.map(\.eventID)))
                uploaded += batch.count
            } catch {
                // 失败即停：保留队列原样等下次重试，不丢事件也不换 eventID
                break
            }
        }
        return uploaded
    }
}
