import Charts
import SwiftUI

/// 学生详情下钻：DTW 时序折线图 + 偏误词列表
struct StudentDetailView: View {
    let student: StudentRowData

    @State private var detailData: StudentDetailData?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── 概览统计 ───────────────────────────
                    statsRow

                    // ── DTW 时序折线图 ─────────────────────
                    dtwChartSection

                    // ── 偏误词列表 ─────────────────────────
                    errorWordsSection
                }
                .padding(20)
            }
            .navigationTitle(student.nickname ?? "学生详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await loadDetail() }
        }
    }

    // MARK: - Sections

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(title: "总练习次数", value: "\(student.totalSessions)", color: .blue)
            statCard(title: "近期通关率",
                     value: String(format: "%.0f%%", student.recentPassRate * 100),
                     color: student.recentPassRate >= 0.6 ? .green : .orange)
        }
    }

    private var dtwChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DTW 进步曲线")
                .font(.headline)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let series = detailData?.dtwTimeSeries, !series.isEmpty {
                Chart {
                    ForEach(Array(series.enumerated()), id: \.offset) { idx, dtw in
                        LineMark(
                            x: .value("第 \(idx + 1) 次", idx + 1),
                            y: .value("DTW", dtw)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.blue)

                        PointMark(
                            x: .value("第 \(idx + 1) 次", idx + 1),
                            y: .value("DTW", dtw)
                        )
                        .foregroundStyle(dtw <= 0.5 ? Color.green : Color.orange)
                    }
                    RuleMark(y: .value("通关线", 0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.red.opacity(0.6))
                }
                .chartYScale(domain: 0...1)
                .frame(height: 180)
            } else {
                emptyChart
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var errorWordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("高频偏误词")
                .font(.headline)

            if let words = detailData?.errorWords, !words.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                        Text(word)
                            .font(.callout.monospaced())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.10))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
            } else if !isLoading {
                Text("暂无偏误词记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyChart: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("暂无练习记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 120)
    }

    // MARK: - Helpers

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func loadDetail() async {
        guard detailData == nil else { return }
        isLoading = true
        detailData = try? await APIClient.shared.fetchStudentDetail(deviceID: student.id)
        isLoading = false
    }
}
