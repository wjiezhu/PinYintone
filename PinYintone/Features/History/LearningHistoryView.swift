import SwiftUI

/// 学习记录（需求 §4 上线范围）。
///
/// **呈现边界**（CLAUDE.md「结果解释边界」、问卷核校要求）：
/// - 这里是**练习日志**，不是能力报告。不写「进步」「提升」「水平」，
///   问卷文案核校要求也明确「不得把『练习记录和变化』译成已经取得进步」。
/// - 不画趋势线、不算平均分：DTW 分数是形成性反馈指标，
///   把它连成曲线会被读成习得效果的证据。
/// - **技术失败单独呈现**：那些记录的分数是哨兵值，不是发音成绩；
///   混进列表会被读成「拿了个负分」。
struct LearningHistoryView: View {
    @State private var sessions: [TrainingSession] = []
    @State private var retryCount = 0

    private var hanzi: (String) -> String {
        { id in CorpusLoader.shared.loadLexemes().first { $0.id == id }?.hanzi ?? id }
    }

    var body: some View {
        List {
            Section {
                summaryRow("history_total_practices", "\(sessions.count)")
                summaryRow("history_words_practiced",
                           "\(Set(sessions.map(\.lexemeID)).count)")
                if retryCount > 0 {
                    // 与成绩分开陈述：这反映录音是否顺利，不是发音水平
                    summaryRow("history_retry_count", "\(retryCount)")
                }
            } header: {
                Text(NSLocalizedString("history_summary", comment: ""))
            } footer: {
                Text(NSLocalizedString("history_footer_note", comment: ""))
            }

            Section(NSLocalizedString("history_recent", comment: "")) {
                if sessions.isEmpty {
                    Text(NSLocalizedString("history_empty", comment: ""))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions, id: \.id) { s in
                        row(s)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("history_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            sessions = SessionRepository.shared.fetchHistory()
            retryCount = SessionRepository.shared.technicalRetryCount()
            ResearchEventLog.shared.log(.historyOpened)
        }
    }

    private func summaryRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(NSLocalizedString(key, comment: ""))
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func row(_ s: TrainingSession) -> some View {
        HStack(spacing: 12) {
            Text(hanzi(s.lexemeID))
                .font(.title3.weight(.medium))
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.timestamp, style: .date)
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(format: NSLocalizedString("history_attempt_n", comment: ""),
                            Int(s.attemptNumber)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            // 只显示通过与否，**不显示分数**——分数是形成性反馈，
            // 脱离当次练习语境列出来容易被当成能力评定
            Label(NSLocalizedString(s.grade == "fail" ? "result_not_passed" : "result_passed",
                                    comment: ""),
                  systemImage: s.grade == "fail" ? "circle" : "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(s.grade == "fail" ? Color.secondary : Color.green)
        }
    }
}
