import Foundation

/// 后台批量同步：将本地 synced=false 的记录上传至云端。
/// 离线安全：单条失败保留 synced=false，下次进入前台/启动重试。
/// 在主线程执行（Repository 使用 viewContext，仅主线程访问）。
@MainActor
final class SyncService {
    static let shared = SyncService()
    private init() {}

    private var isSyncing = false

    /// App 进入前台或启动时调用，依次同步三类记录。
    func syncAll() async {
        guard !isSyncing else { return }   // 防重入
        isSyncing = true
        defer { isSyncing = false }

        await syncSessions()
        await syncAspirations()
        await syncFreeTextRecords()
    }

    func syncSessions() async {
        let repo = SessionRepository.shared
        let pending = repo.fetchUnsynced()
        guard !pending.isEmpty else { return }
        var done: [TrainingSession] = []
        for session in pending {
            let dto = session.toDTO()
            do {
                try await APIClient.shared.syncSession(dto)
                done.append(session)
            } catch {
                // 保留，下次重试
            }
        }
        repo.markSynced(done)
    }

    func syncAspirations() async {
        let repo = AspirationRepository.shared
        let pending = repo.fetchUnsynced()
        guard !pending.isEmpty else { return }
        var done: [AspirationAttempt] = []
        for attempt in pending {
            let dto = attempt.toDTO()
            do {
                try await APIClient.shared.syncAspiration(dto)
                done.append(attempt)
            } catch {
                // 保留，下次重试
            }
        }
        repo.markSynced(done)
    }

    func syncFreeTextRecords() async {
        let repo = FreeTextRepository.shared
        let pending = repo.fetchUnsynced()
        guard !pending.isEmpty else { return }
        var done: [FreeTextRecord] = []
        for record in pending {
            let dto = record.toDTO()
            do {
                try await APIClient.shared.syncFreeText(dto)
                done.append(record)
            } catch {
                // 保留，下次重试
            }
        }
        repo.markSynced(done)
    }
}
