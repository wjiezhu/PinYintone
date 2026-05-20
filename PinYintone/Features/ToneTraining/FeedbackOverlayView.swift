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

            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(color)

                Text(feedbackText)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text(String(format: "DTW %.2f", result.dtwScore))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(action: onDismiss) {
                    Text(continueLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(color)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(40)
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
