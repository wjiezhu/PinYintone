import SwiftUI

/// 关卡 2 和关卡 3 共用的录音按钮
/// 录音中：红色脉冲圆；待机：麦克风图标
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        fatalError("TODO: 实现 — 按住录音 / 松开停止；TimelineView 脉冲动画")
    }
}
