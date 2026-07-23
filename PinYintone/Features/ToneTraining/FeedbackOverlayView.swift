import SwiftUI

/// 评分结果覆盖层：等级图标 + DTW 分数 + 多语种情感反馈文本（论文 3.4）。
///
/// 推进逻辑（P0-1）：是否换词由学习者决定，不再以通关为前提。
/// 旧实现只有通关才 `loadNext()`，导致学习者卡在难词上反复失败直至退出，
/// 词表推进被污染、组间比较失效。现提供"再试一次 / 下一个词"两个明确出口。
struct FeedbackOverlayView: View {
    let result: FeedbackResult
    /// 同词连续失败已达阈值：提示可以先跳过，减轻挫败感
    var showSkipHint: Bool = false
    /// 主操作 / 关闭。`onNext == nil` 时作为唯一按钮（关卡 1 沿用此单按钮形态）
    let onRetry: () -> Void
    /// 提供该回调即启用「再试一次 / 下一个词」双按钮（关卡 2）
    var onNext: (() -> Void)?

    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { onRetry() }

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

                // 连续失败兜底提示：允许直接跳过，避免被难词困住
                if showSkipHint {
                    Text(NSLocalizedString("feedback_skip_hint", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // 推进由学习者决定：再试同一词 / 手动进入下一词
                if let onNext {
                    HStack(spacing: 10) {
                        Button(action: onRetry) {
                            Text(NSLocalizedString("feedback_retry", comment: ""))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button(action: onNext) {
                            Text(NSLocalizedString("feedback_next_word", comment: ""))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(color)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.top, 4)
                } else {
                    // 关卡 1 等场景：保持原有单按钮形态
                    Button(action: onRetry) {
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
