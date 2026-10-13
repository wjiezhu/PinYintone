import SwiftUI

/// 录音键。声调练习、自测、自由文本共用。
///
/// 全 App 统一「**点一下开始，再点一下停止**」，不混用长按（需求 U03）。
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
                // 外圈：一圈同色的淡晕，让它从操作栏里站出来；尺寸恒定
                Circle()
                    .fill((isRecording ? Theme.recording : Theme.accent).opacity(0.16))
                Circle()
                    .fill(isRecording ? Theme.recording : Theme.accent)
                    .frame(width: Theme.recordButton, height: Theme.recordButton)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isRecording ? Color.white : Theme.onAccent)
                    .accessibilityHidden(true)
            }
            // 热区略大于可见圆，且恒定
            .frame(width: Theme.recordButton + 12, height: Theme.recordButton + 12)
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(NSLocalizedString(isRecording ? "record_stop" : "record_start",
                                              comment: ""))
        .accessibilityIdentifier("practice.record")
    }
}
