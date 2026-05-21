import SwiftUI

/// 百分制得分显示：大号分数 + 等级标签（用户友好，不暴露原始 DTW）。
struct DTWScoreView: View {
    let result: FeedbackResult

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(result.score)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text("/100")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var color: Color {
        switch result.grade {
        case .excellent:     return .green
        case .good:          return .mint
        case .needsPractice: return .orange
        case .fail:          return .red
        }
    }

    private var label: String {
        switch result.grade {
        case .excellent:     return NSLocalizedString("grade_excellent", comment: "")
        case .good:          return NSLocalizedString("grade_good", comment: "")
        case .needsPractice: return NSLocalizedString("grade_needs_practice", comment: "")
        case .fail:          return NSLocalizedString("grade_fail", comment: "")
        }
    }
}
