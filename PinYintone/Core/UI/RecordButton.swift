import SwiftUI

/// 关卡 2 和关卡 3 共用的录音按钮。
/// 录音中：红色脉冲圆 + 停止图标；待机：麦克风图标。
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // 录音中的脉冲光晕
                if isRecording {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let scale = 1.0 + 0.15 * sin(t * 3)
                        Circle()
                            .fill(Color.red.opacity(0.25))
                            .frame(width: 96, height: 96)
                            .scaleEffect(scale)
                    }
                }
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 76, height: 76)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 100, height: 100)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording
            ? NSLocalizedString("record_stop", comment: "")
            : NSLocalizedString("record_start", comment: ""))
    }
}
