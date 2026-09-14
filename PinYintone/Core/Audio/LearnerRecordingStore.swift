import Combine
import Foundation

/// 学习者本次录音的暂存（需求 §4「回听」、§7「设备端录音保留与删除方式」）。
///
/// 保留策略（已确认）：**只留当前一条**，换词或重录即覆盖，离开练习即清除。
///
/// 刻意**不落盘**：PCM 只存在内存里。原始录音本来就不上传，
/// 不写文件可以省掉「文件何时删、崩溃后残留怎么办、备份会不会被带走」
/// 一整类问题——这些正是需求把「保留与删除方式」列为上线前必须确认项的原因。
///
/// 代价是进程结束即失去，无法跨启动回听。按当前保留策略这正是想要的行为。
@MainActor
final class LearnerRecordingStore: ObservableObject {
    static let shared = LearnerRecordingStore()

    /// 16 kHz 单声道 PCM。与 `AudioEngine.sampleRate` 一致。
    private(set) var pcm: [Int16] = []
    /// 这条录音属于哪个词条，用于换词时判断是否该清除
    private(set) var lexemeID: String?

    /// 供 UI 驱动「回听」按钮的可用状态
    @Published private(set) var hasRecording = false

    let sampleRate: Double = 16_000

    private init() {}

    /// 存入本次录音，**覆盖**上一条。
    /// 帧数过少的（没录上）不存，避免回听放出一段噪声让人以为坏了。
    func store(pcm samples: [Int16], lexemeID: String?) {
        guard samples.count >= Int(sampleRate * 0.2) else {   // 少于 0.2 秒视为没录上
            clear()
            return
        }
        pcm = samples
        self.lexemeID = lexemeID
        hasRecording = true
    }

    /// 换词时调用：词变了就清掉，避免放出上一个词的录音。
    func clearIfLexemeChanged(to newID: String?) {
        if lexemeID != newID { clear() }
    }

    /// 离开练习、撤回同意或清理本地数据时调用。
    func clear() {
        pcm = []
        lexemeID = nil
        hasRecording = false
    }
}
