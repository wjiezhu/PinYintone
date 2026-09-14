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

    /// 尝试上报待传事件。返回成功上报的条数。
    @discardableResult
    func flush(participantID: String, manifestID: String) async -> Int {
        guard !isUploading else { return 0 }          // 避免并发重复上传
        isUploading = true
        defer { isUploading = false }

        var uploaded = 0
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
