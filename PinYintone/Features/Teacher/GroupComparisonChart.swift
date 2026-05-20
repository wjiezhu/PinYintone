import Charts
import SwiftUI

/// A/B 两组 DTW 均值对比柱状图（Swift Charts，iOS 16+）
/// avgDTW 越低 = 发音越准；通关线 0.5 用红色虚线标示
struct GroupComparisonChart: View {
    let data: GroupComparisonData

    private let passThreshold = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A/B 分组 DTW 对比")
                .font(.headline)

            if data.bars.isEmpty {
                emptyState
            } else {
                Chart {
                    // 柱状图
                    ForEach(data.bars) { bar in
                        BarMark(
                            x: .value("分组", bar.group),
                            y: .value("平均 DTW", bar.avgDTW)
                        )
                        .foregroundStyle(bar.avgDTW <= passThreshold ? Color.green : Color.orange)
                        .annotation(position: .top, alignment: .center) {
                            Text(String(format: "%.2f", bar.avgDTW))
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    // 通关线
                    RuleMark(y: .value("通关线", passThreshold))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.red.opacity(0.7))
                        .annotation(position: .trailing) {
                            Text("≤0.5")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.2f", v))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)

                // 图例
                HStack(spacing: 16) {
                    ForEach(data.bars) { bar in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(bar.avgDTW <= passThreshold ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text("\(bar.group)（n=\(bar.count)）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
                Image(systemName: "chart.bar.xaxis")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("暂无数据")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 140)
    }
}
