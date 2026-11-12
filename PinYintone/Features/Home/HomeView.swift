import SwiftUI

/// 「练习」首页（需求 2.3 版 U02）。
///
/// 自上而下：应用名称与声纹 → 页名 → 需要处理的事（紧凑、可关闭）→
/// **2×2 功能格**（声调、自由文本、送气、我的词条，整格可点）→ 继续练习。
///
/// 声调格排第一并用浅灰绿底，表示它是首要入口。自测不在四格里——
/// 它是声调页里的次级入口。
///
/// 「继续练习」只在**真有练习记录**时出现，显示的是最近实际练过的那个词；
/// 没有记录就只给一个普通的开始入口，不编一条「上次练到」。
/// 点它是打开练习页，**不直接启动麦克风**。
///
/// **不展示**能力等级、平均分趋势、连续打卡、积分或任何「学习提升」的说法。
struct PracticeHomeView: View {
    @ObservedObject private var store = ResearchStore.shared
    @ObservedObject private var config = ResearchConfig.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var path: [Route] = []
    @State private var surveyToOpen: SurveyTarget?
    @State private var showResearchFlow = false
    @State private var lastPracticed: (lexeme: Lexeme, at: Date)?
    @AppStorage("pt_research_home_row_dismissed") private var researchRowDismissed = false

    enum Route: Hashable {
        case tone(lexemeID: String?)
        case freeText, saved, aspiration
        /// 现场实测（已参加研究、配置带实测协议时才出现）
        case fieldSession
    }

    struct SurveyTarget: Identifiable {
        let formKey: String
        var id: String { formKey }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        BrandWordmark()
                        Text(NSLocalizedString("tab_practice", comment: ""))
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    notices
                    modules
                    continueSection
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.background)
            // 导航栏在首页不显示，但标题要给：下一页的返回键用它当文字。
            // 不给的话 iOS 17 / 18 上返回键是系统语言的「Back」，与 App 里选的语言对不上。
            .navigationTitle(NSLocalizedString("tab_practice", comment: ""))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { reloadLastPracticed() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .tone(let id): ToneTrainingView(initialLexemeID: id)
                case .freeText:     FreeTextInputView()
                case .saved:        SavedWordsView()
                case .aspiration:   AspirationView()
                case .fieldSession: ToneTrainingView(startsFieldSession: true)
                }
            }
        }
        .sheet(item: $surveyToOpen) { ResearchSurveySheet(formKey: $0.formKey) }
        .sheet(isPresented: $showResearchFlow) { ResearchJoinFlowView() }
        // 刚登录：取到研究配置后弹一次知情同意（可以不同意，不影响任何功能）
        .task {
            guard store.state.signupConsentDue else { return }
            await ResearchConfig.shared.refresh()
            presentSignupConsentIfDue()
        }
        .onChange(of: config.available?.manifestID) { _ in presentSignupConsentIfDue() }
    }

    private func presentSignupConsentIfDue() {
        if ResearchEnrollment.consumeSignupConsent() { showResearchFlow = true }
    }

    /// 从本机记录里取最近实际练过的词。只读本机，不向服务器要任何人的记录。
    private func reloadLastPracticed() {
        guard let last = SessionRepository.shared.lastPracticedWord(),
              let lexeme = CorpusLoader.shared.orderedPool(category: .tone)
                .first(where: { $0.id == last.lexemeID }) else {
            lastPracticed = nil
            return
        }
        lastPracticed = (lexeme, last.at)
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

    /// 现场实测入口：研究者在场时由学习者点开。配置开着就一直在，不提供关闭
    private var showsFieldSessionRow: Bool {
        _ = config.available          // 配置刷新后重新判断
        return config.fieldSessionAvailable()
    }

    @ViewBuilder
    private var notices: some View {
        let surveys = store.state.surveyBannerDismissed ? [] : SurveyCenter.resumable(in: store.state)
        if !surveys.isEmpty || showsResearchRow || showsFieldSessionRow {
            VStack(spacing: Theme.Space.s) {
                if showsFieldSessionRow {
                    noticeRow(icon: "list.number",
                              title: NSLocalizedString("home_field_session", comment: ""),
                              id: "home.fieldSession",
                              onOpen: { path.append(.fieldSession) },
                              onDismiss: nil)
                }
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
                        .foregroundStyle(Theme.primary)
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
            .buttonStyle(PressableStyle())
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
        .background(Theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }

    // MARK: - 功能格

    private struct Module: Identifiable {
        let route: Route
        let title: String
        let kind: ModuleIllustration.Kind
        let tone: ModuleTile.Tone
        let id: String
    }

    private var moduleList: [Module] {
        [
            Module(route: .tone(lexemeID: nil), title: "stage2_title", kind: .tone,
                   tone: .primary, id: "home.tone"),
            Module(route: .freeText, title: "stage3_title", kind: .freeText,
                   tone: .plain, id: "home.freeText"),
            Module(route: .aspiration, title: "stage1_title", kind: .aspiration,
                   tone: .blue, id: "home.aspiration"),
            Module(route: .saved, title: "saved_words_title", kind: .savedWords,
                   tone: .plain, id: "home.saved"),
        ]
    }

    /// 2×2；放大文字时改成一列（图不压缩成小图标，文字不缩）。
    private var modules: some View {
        let singleColumn = typeSize.isAccessibilitySize
        let columns = singleColumn ? 1 : 2
        let all = moduleList
        let rows = stride(from: 0, to: all.count, by: columns).map {
            Array(all[$0..<min($0 + columns, all.count)])
        }
        return VStack(spacing: Theme.Space.m) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                // 同一行两格等高
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(row) { module in
                        Button {
                            path.append(module.route)
                        } label: {
                            ModuleTile(title: NSLocalizedString(module.title, comment: ""),
                                       kind: module.kind, tone: module.tone, wide: singleColumn)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier(module.id)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 继续练习

    @ViewBuilder
    private var continueSection: some View {
        if let last = lastPracticed {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(NSLocalizedString("home_continue", comment: ""))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Theme.Space.s)
                    // 真实的上次练习时间，取自本机记录
                    Text(last.at, format: .dateTime.month().day().hour().minute())
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: Theme.Space.m) {
                        Text(last.lexeme.hanzi)
                            .font(.title.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        ToneGlyphRow(tones: last.lexeme.tones,
                                     glyphSize: CGSize(width: 24, height: 16), lineWidth: 2.5)
                    }
                    Text(last.lexeme.pinyin)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Button {
                    path.append(.tone(lexemeID: last.lexeme.id))
                } label: {
                    Text(NSLocalizedString("home_continue", comment: ""))
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("home.continueTone")
            }
        } else {
            // 没有练习记录：只给普通入口，不显示任何「上次」
            Button {
                path.append(.tone(lexemeID: nil))
            } label: {
                Text(NSLocalizedString("home_start", comment: ""))
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("home.continueTone")
        }
    }
}
