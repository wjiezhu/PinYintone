import SwiftUI

/// 学生列表：昵称 + 练习数 + 通关率 + 最后活跃时间
struct StudentListView: View {
    let students: [StudentRowData]
    let onSelect: (StudentRowData) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("学生列表（\(students.count) 人）")
                .font(.headline)

            if students.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(students) { student in
                        Button { onSelect(student) } label: {
                            StudentRowView(student: student)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "person.3")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("暂无学生数据")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 120)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 单行学生卡片
private struct StudentRowView: View {
    let student: StudentRowData

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // 头像占位（首字母）
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(initial)
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(student.nickname ?? "游客")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(student.totalSessions) 次练习")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // 通关率
                Text(String(format: "%.0f%%", student.recentPassRate * 100))
                    .font(.subheadline.bold())
                    .foregroundStyle(student.recentPassRate >= 0.6 ? .green : .orange)
                // 最后活跃
                if let date = student.lastActiveAt {
                    Text(Self.relativeFormatter.localizedString(for: date, relativeTo: .now))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }

    private var initial: String {
        (student.nickname ?? "?").prefix(1).uppercased()
    }
}
