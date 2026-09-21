import SwiftUI

/// 「练习建议」面板（需求 §5）。**点击后查看，不强制弹出。**
///
/// 版式即约束：目标词提示与本次反馈**分区显示**（字典 §9），
/// 本次反馈区只放**一条**主建议（需求 §5：每次突出一个主要调整方向），
/// 底部三个入口让人立刻能做点什么：重听示范 / 回听 / 再练一次。
struct PracticeAdviceView: View {
    let advice: PracticeAdvice
    let onPlaySample: () -> Void
    let onReplayOwn: () -> Void
    let onPracticeAgain: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 分区一：这个词该怎么读。**不声称用户发生了偏误**。
                    // 没有已核对提示时整块不渲染——不得套用别词提示。
                    if let hint = advice.teacherHint {
                        section(title: "advice_target_title", body: hint, tint: .accentColor)
                    }

                    // 分区二：这次的情况。只放一条主建议。
                    section(title: "advice_this_time_title",
                            body: NSLocalizedString(advice.mainSentenceKey, comment: ""),
                            tint: .secondary)

                    VStack(spacing: 10) {
                        actionButton("advice_action_listen", "speaker.wave.2") {
                            onPlaySample()
                        }
                        actionButton("advice_action_replay", "waveform") {
                            onReplayOwn()
                        }
                        actionButton("advice_action_again", "arrow.clockwise") {
                            dismiss(); onPracticeAgain()
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle(NSLocalizedString("advice_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common_close", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func section(title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase).kerning(0.8)
                .foregroundStyle(tint)
            Text(body)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func actionButton(_ key: String, _ symbol: String,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(NSLocalizedString(key, comment: ""), systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
