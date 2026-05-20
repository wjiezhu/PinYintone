import SwiftUI

/// 归一化 DTW 得分显示：分数 + 等级标签（通关线 ≤ 0.5）。
struct DTWScoreView: View {
    let score: Float
    let grade: FeedbackGrade

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DTW")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f", score))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(color)
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
        switch grade {
        case .excellent:     return .green
        case .good:          return .mint
        case .needsPractice: return .orange
        case .fail:          return .red
        }
    }

    private var label: String {
        switch grade {
        case .excellent:     return NSLocalizedString("grade_excellent", comment: "")
        case .good:          return NSLocalizedString("grade_good", comment: "")
        case .needsPractice: return NSLocalizedString("grade_needs_practice", comment: "")
        case .fail:          return NSLocalizedString("grade_fail", comment: "")
        }
    }
}
