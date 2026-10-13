import SwiftUI

/// 学习记录（需求 U05）。
///
/// 按日期列出本机的练习：词条、时间、任务类型、本次完成状态。
///
/// **呈现边界**（CLAUDE.md「结果解释边界」）：
/// - 这是**练习日志**，不是能力报告。不写「进步」「提升」「水平」。
/// - 不画趋势线、不算平均分、不比较首次与末次——形成性反馈连成曲线
///   会被读成习得效果的证据。
/// - **技术失败单独标记**：那些记录没有成绩（旧表里是哨兵值），
///   显示成「未录到」，不显示成低分，也不混进「通过 / 再练」里。
/// - 自测记录只显示「已录」：自测本来就不给评价，记录页也不补给。
/// - 只读本机数据，不从服务器或研究库取任何人的资料来填充。
struct LearningHistoryView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var filter: HistoryEntry.Kind?

    private var visible: [HistoryEntry] {
        guard let filter else { return entries }
        return entries.filter { $0.kind == filter }
    }

    /// 按自然日分组，最近的在前
    private var days: [(day: Date, items: [HistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.timestamp) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                Picker(NSLocalizedString("history_filter", comment: ""), selection: $filter) {
                    Text(NSLocalizedString("history_filter_all", comment: ""))
                        .tag(HistoryEntry.Kind?.none)
                    ForEach(HistoryEntry.Kind.allCases, id: \.self) { kind in
                        Text(NSLocalizedString(kind.labelKey, comment: ""))
                            .tag(HistoryEntry.Kind?.some(kind))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("history.filter")

                if visible.isEmpty {
                    emptyState
                } else {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(group.day, format: .dateTime.year().month().day().weekday(.wide))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityAddTraits(.isHeader)
                            GroupedCard {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { RowDivider() }
                                    row(entry)
                                }
                            }
                        }
                    }
                    Text(NSLocalizedString("history_footer_note", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("history_title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            entries = HistoryEntry.loadAll()
            // 只在页面实际打开时记一次；筛选、滚动不重复记
            ResearchEventLog.shared.log(.historyOpened)
        }
    }

    /// 真实的空状态：没有记录就说没有，不放示例
    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(NSLocalizedString(entries.isEmpty ? "history_empty" : "history_empty_filtered",
                                   comment: ""))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("history.empty")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .surfaceCard()
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .environment(\.layoutDirection, .leftToRight)
                HStack(spacing: Theme.Space.xs) {
                    Text(entry.timestamp, format: .dateTime.hour().minute())
                        .monospacedDigit()
                    Text("·").accessibilityHidden(true)
                    Text(NSLocalizedString(entry.kind.labelKey, comment: ""))
                }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.s)
            statusView(entry.status)
        }
        .padding(.vertical, Theme.Space.m)
        .frame(minHeight: Theme.minTap)
        .accessibilityElement(children: .combine)
    }

    /// 状态同时用图标和文字表达，不单靠颜色
    @ViewBuilder
    private func statusView(_ status: HistoryEntry.Status) -> some View {
        Label {
            Text(NSLocalizedString(status.labelKey, comment: ""))
        } icon: {
            Image(systemName: status.icon).accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(status == .technicalFailure ? Theme.warning
                         : (status == .passed ? Theme.accent : Theme.textSecondary))
        .multilineTextAlignment(.trailing)
    }
}

/// 记录页的一行。声调练习、自测、自由文本三种来源统一成同一个形状。
struct HistoryEntry: Identifiable, Equatable {
    enum Kind: CaseIterable {
        case fixedWord, freeText, selfTest

        var labelKey: String {
            switch self {
            case .fixedWord: return "history_kind_fixed"
            case .freeText:  return "history_kind_free"
            case .selfTest:  return "history_kind_self_test"
            }
        }
    }

    enum Status: Equatable {
        /// 本次通过
        case passed
        /// 本次未通过。措辞是「再练」，不是评级
        case notPassed
        /// 已完成录音，没有评价（自测、自由文本）
        case recorded
        /// 技术原因没录成。**没有成绩**
        case technicalFailure

        var labelKey: String {
            switch self {
            case .passed: return "result_passed"
            case .notPassed: return "result_not_passed"
            case .recorded: return "history_status_recorded"
            case .technicalFailure: return "history_status_technical"
            }
        }

        var icon: String {
            switch self {
            case .passed: return "checkmark.circle.fill"
            case .notPassed: return "arrow.counterclockwise.circle"
            case .recorded: return "waveform"
            case .technicalFailure: return "exclamationmark.triangle.fill"
            }
        }
    }

    let id: UUID
    let title: String
    let timestamp: Date
    let kind: Kind
    let status: Status

    /// 由一条声调记录生成。技术失败按 `resultStatus` 识别，**不看分数**——
    /// 它的分数是 -1 哨兵，不是成绩。
    init(session s: TrainingSession, hanzi: (String) -> String) {
        id = s.id
        title = hanzi(s.lexemeID)
        timestamp = s.timestamp
        // 自测，以及升级前的前测 / 后测，都是不给评价的测试类记录
        let assessment = TrainingPhase(rawValue: s.phase ?? "")?.isAssessment ?? false
        kind = assessment ? .selfTest : .fixedWord
        if s.resultStatus == ResultStatus.technicalRetry.rawValue {
            status = .technicalFailure
        } else if assessment {
            status = .recorded
        } else {
            status = s.grade == FeedbackGrade.fail.rawValue ? .notPassed : .passed
        }
    }

    init(freeText r: FreeTextRecord) {
        id = r.id
        title = r.tokenizedWord
        timestamp = r.timestamp
        kind = .freeText
        status = .recorded
    }

    init(id: UUID, title: String, timestamp: Date, kind: Kind, status: Status) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.kind = kind
        self.status = status
    }

    @MainActor
    static func loadAll() -> [HistoryEntry] {
        let lexemes = Dictionary(uniqueKeysWithValues:
            CorpusLoader.shared.loadLexemes().map { ($0.id, $0.hanzi) })
        let tone = SessionRepository.shared.fetchAllForHistory()
            .map { HistoryEntry(session: $0) { lexemes[$0] ?? $0 } }
        let free = FreeTextRepository.shared.fetchHistory().map(HistoryEntry.init(freeText:))
        return (tone + free).sorted { $0.timestamp > $1.timestamp }
    }
}
