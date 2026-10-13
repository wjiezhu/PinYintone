import SwiftUI

/// 录音键。声调练习、自测、自由文本共用。
///
/// 全 App 统一「**点一下开始，再点一下停止**」，不混用长按（需求 U03）。
/// 待录是深松绿底、白色麦克风与「录音」；录音中换成陶红底、停止图标与「停止」——
/// **图标和文字都变，不只是变色**。
/// 外框尺寸固定：待录、录音中、不可用三种状态下按钮不变大变小，
/// 所以它在底部操作栏里的位置一毫米都不动。
struct RecordButton: View {
    let isRecording: Bool
    /// 分析中、参考未就绪时为 false：按钮变淡且不可点，但仍占着原来的位置
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Theme.learnerAccent : Theme.primary)
                VStack(spacing: 2) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(height: 26)
                    // 圆里只容得下一个短词，字号固定；完整说明由无障碍标签给出
                    Text(NSLocalizedString(isRecording ? "bar_stop" : "record_short", comment: ""))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(isRecording ? Theme.onLearnerAccent : Theme.onPrimary)
                .accessibilityHidden(true)
            }
            .frame(width: Theme.recordButton, height: Theme.recordButton)
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(NSLocalizedString(isRecording ? "record_stop" : "record_start",
                                              comment: ""))
        .accessibilityIdentifier("practice.record")
    }
}
