import Foundation

/// 后台批量同步：将本地 synced=false 的记录上传至云端
final class SyncService {
    static let shared = SyncService()
    private init() {}

    func syncSessions() async {
        fatalError("TODO: 实现")
    }

    func syncAspirations() async {
        fatalError("TODO: 实现")
    }

    func syncFreeTextRecords() async {
        fatalError("TODO: 实现")
    }

    /// 启动时调用，依次同步三类记录
    func syncAll() async {
        fatalError("TODO: 实现")
    }
}
