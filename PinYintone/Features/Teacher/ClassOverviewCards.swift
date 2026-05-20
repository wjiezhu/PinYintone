import SwiftUI

/// 三张概览卡片：班级人数 / 平均 DTW / 整体通关率
struct ClassOverviewCards: View {
    let summary: ClassSummary?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                  spacing: 12) {
            OverviewCard(
                icon: "person.3.fill",
                color: .blue,
                title: "学生人数",
                value: summary.map { "\($0.totalStudents)" } ?? "--",
                trend: summary?.weeklyNewStudents.map { "+\($0) 本周" }
            )
            OverviewCard(
                icon: "waveform.path.ecg",
                color: .purple,
                title: "平均 DTW",
                value: summary.map { String(format: "%.2f", $0.avgDTW) } ?? "--",
                trend: nil
            )
            OverviewCard(
                icon: "checkmark.seal.fill",
                color: .green,
                title: "通关率",
                value: summary.map { String(format: "%.0f%%", $0.passRate * 100) } ?? "--",
                trend: nil
            )
        }
    }
}

struct OverviewCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let trend: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let trend {
                Text(trend)
                    .font(.caption2)
                    .foregroundStyle(color)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
