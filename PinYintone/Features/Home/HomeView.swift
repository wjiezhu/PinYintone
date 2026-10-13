import SwiftUI

/// 「练习」首页（需求 U02）。
///
/// 一个连续的系统列表，自上而下：
/// 1. 需要处理的事（继续填写问卷、参加研究）——各一条紧凑、可关闭的行，不挡练习
/// 2. 声调练习：当前词与「继续练习」入口，打开首页就看得见
/// 3. 词条列表：直接展示真实词库，点哪个练哪个
/// 4. 更多练习：自由文本、收藏、送气——次级入口，不与声调争视觉层级
///
/// **不展示**能力等级、平均分趋势、连续打卡或任何「学习提升」的说法。
/// 没有练习记录时就只有词库，不编示例数据。
struct PracticeHomeView: View {
    @ObservedObject private var store = ResearchStore.shared
    @ObservedObject private var config = ResearchConfig.shared
    @ObservedObject private var sequencer = ToneSequencer.shared
    @ObservedObject private var localization = LocalizationManager.shared

    @State private var path: [Route] = []
    @State private var surveyToOpen: SurveyTarget?
    @State private var showResearchFlow = false
    @AppStorage("pt_research_home_row_dismissed") private var researchRowDismissed = false

    enum Route: Hashable {
        case tone(lexemeID: String?)
        case freeText, saved, aspiration
    }

    struct SurveyTarget: Identifiable {
        let formKey: String
        var id: String { formKey }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                noticeSection
                toneSection
                wordsSection
                moreSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Pinyintone")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .tone(let id): ToneTrainingView(initialLexemeID: id)
                case .freeText:     FreeTextInputView()
                case .saved:        SavedWordsView()
                case .aspiration:   AspirationView()
                }
            }
        }
        .sheet(item: $surveyToOpen) { ResearchSurveySheet(formKey: $0.formKey) }
        .sheet(isPresented: $showResearchFlow) { ResearchJoinFlowView() }
    }

    // MARK: - 需要处理的事

    /// 是否显示「参加研究」那一行。自动只邀请一次：用户关掉或明确拒绝后不再出现在首页，
    /// 入口仍在设置里；已同意但流程没走完的，保留一行方便接着做。
    private var showsResearchRow: Bool {
        guard ResearchEnrollment.canJoinNow() else { return false }
        switch store.state.participation {
        case .notAsked: return !researchRowDismissed
        case .consentedPending: return true
        default: return false
        }
    }

    @ViewBuilder
    private var noticeSection: some View {
        let surveys = store.state.surveyBannerDismissed ? [] : SurveyCenter.resumable(in: store.state)
        if !surveys.isEmpty || showsResearchRow {
            Section {
                ForEach(surveys) { record in
                    noticeRow(icon: "square.and.pencil",
                              title: NSLocalizedString(record.formKey == SurveyCenter.preKey
                                                       ? "home_survey_pre" : "home_survey_post",
                                                       comment: ""),
                              id: "home.survey.\(record.formKey)",
                              onOpen: { surveyToOpen = .init(formKey: record.formKey) },
                              onDismiss: { SurveyCenter.dismissBanner() })
                }
                if showsResearchRow {
                    noticeRow(icon: "person.badge.plus",
                              title: NSLocalizedString(
                                store.state.participation == .consentedPending
                                    ? "home_research_resume" : "home_research_invite", comment: ""),
                              id: "home.research",
                              onOpen: { showResearchFlow = true },
                              // 已经同意、只是没走完的不提供关闭：关了就找不到下一步了
                              onDismiss: store.state.participation == .notAsked
                                  ? { researchRowDismissed = true } : nil)
                }
            }
        }
    }

    /// 一条紧凑的提示行：点开处理，或点右边的 × 关掉。不是横幅，也不是进度条。
    private func noticeRow(icon: String, title: String, id: String,
                           onOpen: @escaping () -> Void,
                           onDismiss: (() -> Void)?) -> some View {
        HStack(spacing: Theme.Space.m) {
            Button(action: onOpen) {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: Theme.minTap, height: Theme.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("common_dismiss", comment: ""))
                .accessibilityIdentifier("\(id).dismiss")
            }
        }
    }

    // MARK: - 声调练习

    private var toneSection: some View {
        Section {
            Button {
                path.append(.tone(lexemeID: nil))
            } label: {
                HStack(spacing: Theme.Space.l) {
                    if let lexeme = sequencer.currentLexeme {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lexeme.hanzi)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(lexeme.pinyin)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .environment(\.layoutDirection, .leftToRight)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Label(NSLocalizedString("home_continue", comment: ""), systemImage: "mic.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, Theme.Space.l)
                        .frame(minHeight: Theme.minTap)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                }
                .padding(.vertical, Theme.Space.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.continueTone")
        } header: {
            Text(NSLocalizedString("stage2_title", comment: ""))
        }
    }

    private var wordsSection: some View {
        Section {
            ForEach(CorpusLoader.shared.orderedPool(category: .tone)) { lexeme in
                Button {
                    path.append(.tone(lexemeID: lexeme.id))
                } label: {
                    WordRow(lexeme: lexeme, language: localization.language)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.word.\(lexeme.id)")
            }
        } header: {
            Text(NSLocalizedString("home_words", comment: ""))
        }
    }

    // MARK: - 更多练习

    private var moreSection: some View {
        Section {
            NavigationLink(value: Route.freeText) {
                Label(NSLocalizedString("stage3_title", comment: ""), systemImage: "text.cursor")
            }
            .accessibilityIdentifier("home.freeText")
            NavigationLink(value: Route.saved) {
                Label(NSLocalizedString("saved_words_title", comment: ""), systemImage: "bookmark")
            }
            .accessibilityIdentifier("home.saved")
            NavigationLink(value: Route.aspiration) {
                Label(NSLocalizedString("stage1_title", comment: ""), systemImage: "wind")
            }
            .accessibilityIdentifier("home.aspiration")
        } header: {
            Text(NSLocalizedString("home_more", comment: ""))
        }
    }
}
