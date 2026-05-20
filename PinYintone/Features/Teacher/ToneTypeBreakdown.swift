import Charts
import SwiftUI

/// 按声调类型（T1/T2/T3/T4）的偏误率横向柱状图
struct ToneTypeBreakdown: View {
    let data: ToneBreakdownData

    // T1→蓝，T2→绿，T3→橙，T4→红
    private func color(for tone: String) -> Color {
        switch tone {
        case "T1": return .blue
        case "T2": return .green
        case "T3": return .orange
        case "T4": return .red
        default:   return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("各声调偏误分布")
                .font(.headline)

            if data.items.isEmpty {
                emptyState
            } else {
                Chart {
                    ForEach(data.items) { item in
                        BarMark(
                            x: .value("偏误率", item.errorRate),
                            y: .value("声调", item.toneType)
                        )
                        .foregroundStyle(color(for: item.toneType))
                        .annotation(position: .trailing) {
                            Text(String(format: "%.0f%%", item.errorRate * 100))
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("暂无数据")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 100)
    }
}
