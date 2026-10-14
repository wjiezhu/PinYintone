import AVFoundation

/// 麦克风权限。
///
/// `AVAudioApplication` 是 iOS 17 才有的；iOS 16（iPhone 8 / 8 Plus / X 能装的最高系统）
/// 上用 `AVAudioSession` 的同名接口，含义相同。全 App 一律经这里查询和申请，
/// 不直接调用两者中的任何一个。
nonisolated enum MicPermission {

    enum State { case undetermined, denied, granted }

    static var state: State {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            default: return .undetermined
            }
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    /// 弹出系统授权框（只有还没问过时才真的弹），返回是否允许。
    static func request() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
