import SwiftUI

/// 评分结果覆盖层：等级图标 + DTW 分数 + 多语种情感反馈文本（论文 3.4）。
struct FeedbackOverlayView: View {
    let result: FeedbackResult
    let onDismiss: () -> Void

    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // 优秀评分：彩带庆祝
            if result.grade == .excellent {
                ConfettiView().ignoresSafeArea()
            }

            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(color)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(result.score)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                    Text("/100")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text(feedbackText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // 按字诊断格（A、B 两组都看，论文 3.4 共享反馈）
                if !result.segments.isEmpty {
                    ToneDiagnosticGrid(segments: result.segments)
                        .padding(.top, 4)
                }

                Button(action: onDismiss) {
                    Text(continueLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(color)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(24)
        }
    }

    private var feedbackText: String {
        FeedbackTemplateLoader.shared.template(for: result.grade, language: localization.language)
    }

    private var continueLabel: String {
        result.grade == .fail
            ? NSLocalizedString("feedback_retry", comment: "")
            : NSLocalizedString("feedback_continue", comment: "")
    }

    private var icon: String {
        switch result.grade {
        case .excellent:     return "star.fill"
        case .good:          return "hand.thumbsup.fill"
        case .needsPractice: return "figure.run"
        case .fail:          return "arrow.clockwise"
        }
    }

    private var color: Color {
        switch result.grade {
        case .excellent:     return .green
        case .good:          return .mint
        case .needsPractice: return .orange
        case .fail:          return .red
        }
    }
}
