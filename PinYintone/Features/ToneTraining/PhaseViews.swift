import SwiftUI

/// 阶段横幅：录音前明确告知当前阶段、任务目标与进度（升级需求 §4.2）。
/// 裸测阶段额外说明"这一轮不会给评价"，避免学习者误以为 App 坏了。
struct PhaseBannerView: View {
    let phase: TrainingPhase
    let progress: (index: Int, total: Int)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(NSLocalizedString(phase.localizationKey, comment: ""))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.index) / \(progress.total)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(NSLocalizedString("phase_goal_\(phase.rawValue)", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch phase {
        case .pretest:  return "square.and.pencil"
        case .training: return "waveform.and.mic"
        case .posttest: return "flag.checkered"
        }
    }
}

/// 裸测录音区：只呈现"正在录 / 未在录"的状态，绝不透露任何音高或评价信息。
/// 这是前后测可比性的前提——一旦这里泄露曲线，前测就不再是裸测。
struct BlindRecordingView: View {
    let isRecording: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isRecording ? "waveform.circle.fill" : "mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(isRecording ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, isActive: isRecording)
            Text(NSLocalizedString(isRecording ? "blind_recording" : "blind_ready",
                                   comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 阶段完成态：走完固定测试词集后的收尾页。同样不含任何成绩信息。
struct PhaseCompleteView: View {
    let phase: TrainingPhase

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(NSLocalizedString("phase_complete_title", comment: ""))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("phase_complete_\(phase.rawValue)", comment: ""))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
