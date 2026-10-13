import SwiftUI

/// 「练习」首页（需求 U02）。
///
/// 一个连续的内容区，自上而下：
/// 1. 需要处理的事（继续填写问卷、参加研究）——各一条紧凑、可关闭的行，不挡练习
/// 2. 声调练习：当前词与「继续练习」入口，打开首页就看得见
/// 3. 词条：直接展示真实词库，点哪个练哪个
/// 4. 更多练习：自由文本、收藏、送气——次级入口，不与声调争视觉层级
///
/// **不展示**能力等级、平均分趋势、连续打卡或任何「学习提升」的说法。
/// 没有练习记录时就只有词库，不编示例数据。
struct PracticeHomeView: View {
    @ObservedObject private var store = ResearchStore.shared
    @ObservedObject private var config = ResearchConfig.shared
    @ObservedObject private var sequencer = ToneSequencer.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dynamicTypeSize) private var typeSize

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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    notices
                    toneSection
                    wordsSection
                    moreSection
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xl)
            }
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
    private var notices: some View {
        let surveys = store.state.surveyBannerDismissed ? [] : SurveyCenter.resumable(in: store.state)
        if !surveys.isEmpty || showsResearchRow {
            VStack(spacing: Theme.Space.s) {
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
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if onDismiss == nil {
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, Theme.Space.m)
                .padding(.trailing, onDismiss == nil ? Theme.Space.m : 0)
                .padding(.vertical, Theme.Space.s)
                .frame(minHeight: Theme.minTap + 4)
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
        .background(Theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius)
            .strokeBorder(Theme.accent.opacity(0.35)))
    }

    // MARK: - 声调练习

    /// 当前词 + 「继续练习」。整块可点。
    private var toneSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(key: "stage2_title")
            Button {
                path.append(.tone(lexemeID: nil))
            } label: {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if let lexeme = sequencer.currentLexeme {
                        currentWord(lexeme)
                    }
                    Label(NSLocalizedString("home_continue", comment: ""), systemImage: "mic.fill")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .padding(.horizontal, Theme.Space.l)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.continueTone")
        }
    }

    private func currentWord(_ lexeme: Lexeme) -> some View {
        let gloss = lexeme.glosses(for: localization.language).primary
        return HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(lexeme.hanzi)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .environment(\.layoutDirection, .leftToRight)
                Text(lexeme.pinyin)
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .environment(\.layoutDirection, .leftToRight)
                if !gloss.isEmpty {
                    Text(gloss)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            ToneGlyphRow(tones: lexeme.tones,
                         glyphSize: CGSize(width: 34, height: 24), lineWidth: 3.5)
                .padding(.top, Theme.Space.s)
        }
    }

    // MARK: - 词条

    private var wordsSection: some View {
        let words = CorpusLoader.shared.orderedPool(category: .tone)
        // 放大文字时一行放不下两张，改成单列（不靠缩字解决）
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: words.count, by: columns).map {
            Array(words[$0..<min($0 + columns, words.count)])
        }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(key: "home_words")
            VStack(spacing: Theme.Space.s) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    // 同一行的两张卡等高：按较高的那张取齐
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        ForEach(row) { lexeme in
                            Button {
                                path.append(.tone(lexemeID: lexeme.id))
                            } label: {
                                WordTile(lexeme: lexeme, language: localization.language,
                                         isCurrent: lexeme.id == sequencer.currentLexeme?.id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.word.\(lexeme.id)")
                        }
                        if row.count < columns {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 更多练习

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(key: "home_more")
            GroupedCard {
                moreRow(.freeText, icon: "text.cursor", title: "stage3_title",
                        subtitle: "stage3_subtitle", id: "home.freeText")
                RowDivider()
                moreRow(.saved, icon: "bookmark", title: "saved_words_title",
                        subtitle: nil, id: "home.saved")
                RowDivider()
                moreRow(.aspiration, icon: "wind", title: "stage1_title",
                        subtitle: "stage1_subtitle", id: "home.aspiration")
            }
        }
    }

    private func moreRow(_ route: Route, icon: String, title: String,
                         subtitle: String?, id: String) -> some View {
        NavigationLink(value: route) {
            EntryRow(icon: icon,
                     title: NSLocalizedString(title, comment: ""),
                     subtitle: subtitle.map { NSLocalizedString($0, comment: "") })
                .padding(.vertical, Theme.Space.m)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
