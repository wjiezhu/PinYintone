import SwiftUI

/// 问卷界面：**每屏一题**，题号与进度明确，底部三个按钮位置固定（需求 U06）。
///
/// 几条不能省的规则（问卷文档 §1、字典 §11）：
/// - 跳过、「无法判断」、「没有困难」是**三种不同的回答**，分别保存。
///   「无法判断」是一个选项；「跳过」是底部的按钮。
/// - 互斥选项（如「不愿回答」）与其余选项不能同选。
/// - 多选有上限时超出要拦住（PRE06 最多 2 项）。
/// - 「其他」的补充文字只在该选项被选中时提交；取消选中就丢掉，不残留在答案里。
/// - 自由文本一律提示不要填写可识别个人身份的信息。
///
/// 本视图只管作答。草稿由外部保存（每次变化都回调），所以返回、切后台、
/// 重启之后回来还在原来那一题。语言在邀请时定下，这里只照着显示。
struct SurveyFormView: View {
    let form: SurveyForm
    /// 这份问卷的语言（邀请时定下的），题面与按钮都用它
    let language: String
    let onDraftChange: (SurveyDraft) -> Void
    let onSubmit: ([SurveyAnswer]) -> Void
    /// 「稍后填写」。nil 则不提供
    var onLater: (() -> Void)?
    /// 「不填写，继续使用」。nil 则不提供
    var onDecline: (() -> Void)?

    @State private var draft: SurveyDraft
    @State private var limitWarning = false
    @State private var showCountryPicker = false
    @FocusState private var textFocused: Bool

    init(form: SurveyForm, language: String, draft: SurveyDraft,
         onDraftChange: @escaping (SurveyDraft) -> Void,
         onSubmit: @escaping ([SurveyAnswer]) -> Void,
         onLater: (() -> Void)? = nil, onDecline: (() -> Void)? = nil) {
        self.form = form
        self.language = language
        self.onDraftChange = onDraftChange
        self.onSubmit = onSubmit
        self.onLater = onLater
        self.onDecline = onDecline
        var d = draft
        d.index = min(max(d.index, 0), max(form.questions.count - 1, 0))
        _draft = State(initialValue: d)
    }

    private var question: SurveyForm.Question { form.questions[draft.index] }
    private var isLast: Bool { draft.index == form.questions.count - 1 }
    private func ui(_ key: String) -> String { SurveyUIStrings.text(key, language) }
    private func localized(_ dict: [String: String]?) -> String? {
        dict?[language] ?? dict?["en"] ?? dict?["zh"]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                progressHeader

                if draft.index == 0, let intro = localized(form.intro) {
                    Text(intro)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(localized(question.question) ?? question.questionId)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(selectionHint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                if let hint = localized(question.hint) {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(question.options, id: \.code) { opt in
                        optionRow(opt)
                    }
                    if usesCountryList {
                        ForEach(extraCountries, id: \.self) { code in
                            countryRow(code)
                        }
                        Button {
                            showCountryPicker = true
                        } label: {
                            Label(ui("search_country"), systemImage: "magnifyingglass")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.primary)
                                .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("survey.countrySearch")
                    }
                }

                if question.type == "text" { textAnswer }

                if limitWarning, let maxN = question.maxSelections {
                    StatusLabel(kind: .warning,
                                text: maxN == 2 ? ui("max_two_error")
                                    : String(format: NSLocalizedString("survey_max_selections", comment: ""), maxN))
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        // 底部按钮钉在安全区之上：键盘弹出时跟着上移，提交键不会被挡住
        .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
        .navigationTitle(localized(form.title) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onLater {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ui("later")) { onLater() }
                        .accessibilityIdentifier("survey.later")
                }
            }
            if let onDecline {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(ui("decline_survey"), role: .destructive) { onDecline() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(NSLocalizedString("common_more", comment: ""))
                    }
                    .accessibilityIdentifier("survey.more")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(NSLocalizedString("settings_done", comment: "")) { textFocused = false }
            }
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(language: language,
                               selected: Set(draft.selections[question.questionId] ?? []),
                               title: ui("search_country")) { code in
                toggleCountry(code)
            }
        }
        // 问卷的阅读方向跟着它自己的语言，不跟 App 当前语言
        .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
    }

    // MARK: - 头部

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("\(draft.index + 1) / \(form.questions.count)")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(String(format: NSLocalizedString("survey_progress_a11y", comment: ""),
                                           draft.index + 1, form.questions.count))
            ProgressView(value: Double(draft.index + 1), total: Double(form.questions.count))
                .tint(Theme.primary)
                .accessibilityHidden(true)
        }
    }

    private var selectionHint: String {
        switch question.type {
        case "single": return ui("select_one")
        case "multi":  return question.maxSelections == 2 ? ui("select_max_two") : ui("select_multiple")
        default:       return ui("optional")
        }
    }

    // MARK: - 选项

    private var usesCountryList: Bool { question.optionSource != nil }

    /// 列表里没有预置、由用户从国家列表里选的国籍
    private var extraCountries: [String] {
        let preset = Set(question.options.map(\.code))
        return (draft.selections[question.questionId] ?? []).filter { !preset.contains($0) }.sorted()
    }

    private func isChosen(_ code: String) -> Bool {
        draft.selections[question.questionId]?.contains(code) == true
    }

    @ViewBuilder
    private func optionRow(_ opt: SurveyForm.Option) -> some View {
        let chosen = isChosen(opt.code)
        Button {
            toggle(opt)
        } label: {
            choiceLabel(text: localized(opt.label) ?? opt.code, chosen: chosen,
                        single: question.type == "single")
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("survey.option.\(opt.code)")

        // 选中「其他」才展示补充输入框，且不强制填写
        if chosen, let input = opt.textInput {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                TextField(localized(input.hint) ?? ui("other_optional"),
                          text: textBinding("\(question.questionId).\(opt.code)", limit: input.maxChars),
                          axis: .vertical)
                    .frame(minHeight: 28)
                    .surfaceCard(padding: Theme.Space.m)
                    .focused($textFocused)
                Text(ui("privacy_hint"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, Theme.Space.xs)
        }
    }

    private func countryRow(_ code: String) -> some View {
        Button {
            toggleCountry(code)
        } label: {
            choiceLabel(text: CountryPickerSheet.name(for: code, language: language),
                        chosen: true, single: false)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isSelected)
    }

    /// 单选用圆钮，多选用复选框（需求 U06）。每个选项一格；
    /// 选中状态同时靠图标形状、描边和颜色表达。
    private func choiceLabel(text: String, chosen: Bool, single: Bool) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Image(systemName: chosen
                  ? (single ? "largecircle.fill.circle" : "checkmark.square.fill")
                  : (single ? "circle" : "square"))
                .font(.title3)
                .foregroundStyle(chosen ? Theme.primary : Theme.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.body.weight(chosen ? .medium : .regular))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .padding(Theme.Space.m)
        .background(chosen ? Theme.primary.opacity(0.08) : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius)
            .strokeBorder(chosen ? Theme.primary : Theme.border, lineWidth: chosen ? 1.5 : 1))
        .contentShape(Rectangle())
    }

    private var textAnswer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextEditor(text: textBinding(question.questionId,
                                         limit: question.textInput?.maxChars ?? 500))
                .frame(minHeight: 140)
                .padding(Theme.Space.s)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
                .focused($textFocused)
                .accessibilityIdentifier("survey.text")
            Text(ui((question.textInput?.maxChars ?? 500) <= 200 ? "limit_200" : "limit_500"))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if question.hint == nil {
                Text(ui("privacy_hint"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 底部按钮（位置固定）

    /// 上一题 · 跳过 · 下一题/提交。三个位置始终存在：第一题时「上一题」禁用而不是消失，
    /// 否则右边两个按钮会在翻页时横向挪位。文字长时允许换行，不缩字。
    private var navigationBar: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            Button(ui("previous")) {
                move(-1)
            }
            .buttonStyle(SecondaryButtonStyle(fillsHeight: true))
            .disabled(draft.index == 0)
            .accessibilityIdentifier("survey.previous")

            Button(ui("skip_question")) {
                skipCurrent()
            }
            .buttonStyle(SecondaryButtonStyle(fillsHeight: true))
            .accessibilityIdentifier("survey.skip")

            Button(isLast ? ui("submit") : ui("next")) {
                if isLast { submit() } else { move(1) }
            }
            .buttonStyle(PrimaryButtonStyle(fillsHeight: true))
            .accessibilityIdentifier(isLast ? "survey.submit" : "survey.next")
        }
        // 三个按钮等高：文字长的那个换行时，另外两个跟着长高，不会参差
        .fixedSize(horizontal: false, vertical: true)
        .bottomBarSurface()
    }

    // MARK: - 作答逻辑

    private func commit(_ change: (inout SurveyDraft) -> Void) {
        change(&draft)
        onDraftChange(draft)
    }

    private func textBinding(_ key: String, limit: Int) -> Binding<String> {
        Binding(
            get: { draft.texts[key] ?? "" },
            set: { new in
                // 按 Unicode 字符截断，不按字节——阿拉伯文按字节会被误判超长
                let clipped = String(new.prefix(limit))
                commit { d in
                    d.texts[key] = clipped.isEmpty ? nil : clipped
                    if key == question.questionId {      // 自由文本题：写了字就不算跳过
                        d.skipped.removeAll { $0 == key }
                        d.answeredAt[key] = Date()
                    }
                }
            })
    }

    private func toggle(_ opt: SurveyForm.Option) {
        let q = question
        var current = Set(draft.selections[q.questionId] ?? [])
        let exclusives = form.exclusiveCodes(in: q)
        limitWarning = false

        if q.type == "single" {
            current = [opt.code]
        } else if current.contains(opt.code) {
            current.remove(opt.code)
        } else if exclusives.contains(opt.code) {
            current = [opt.code]                 // 互斥选项：清掉其余全部
        } else {
            current.subtract(exclusives)         // 选普通项时先清掉互斥项
            if let maxN = q.maxSelections, current.count >= maxN {
                limitWarning = true
                return
            }
            current.insert(opt.code)
        }
        store(selection: current, for: q)
    }

    private func toggleCountry(_ code: String) {
        let q = question
        var current = Set(draft.selections[q.questionId] ?? [])
        if current.contains(code) {
            current.remove(code)
        } else {
            current.subtract(form.exclusiveCodes(in: q))
            current.insert(code)
        }
        store(selection: current, for: q)
    }

    private func store(selection: Set<String>, for q: SurveyForm.Question) {
        commit { d in
            d.selections[q.questionId] = selection.isEmpty ? nil : selection.sorted()
            d.skipped.removeAll { $0 == q.questionId }
            d.answeredAt[q.questionId] = Date()
            // 取消了带补充文字的选项：文字一并丢掉，不留在草稿里
            for opt in q.options where opt.textInput != nil && !selection.contains(opt.code) {
                d.texts["\(q.questionId).\(opt.code)"] = nil
            }
        }
    }

    private func skipCurrent() {
        let q = question
        commit { d in
            if !d.skipped.contains(q.questionId) { d.skipped.append(q.questionId) }
            d.selections[q.questionId] = nil
            d.answeredAt[q.questionId] = Date()
            // 跳过即不留任何内容：选项的补充文字、自由文本都清掉
            d.texts = d.texts.filter { $0.key != q.questionId && !$0.key.hasPrefix("\(q.questionId).") }
        }
        if isLast { submit() } else { move(1) }
    }

    private func move(_ delta: Int) {
        textFocused = false
        limitWarning = false
        commit { d in d.index = min(max(d.index + delta, 0), form.questions.count - 1) }
    }

    private func submit() {
        textFocused = false
        onSubmit(Self.answers(for: form, draft: draft))
    }

    /// 由草稿生成逐题答案。三种状态分别保存，**不用空值推断「没有问题」**。
    static func answers(for form: SurveyForm, draft: SurveyDraft, now: Date = Date()) -> [SurveyAnswer] {
        form.questions.map { q in
            let stamp = draft.answeredAt[q.questionId] ?? now
            if let codes = draft.selections[q.questionId], !codes.isEmpty {
                // 「其他」的补充文字只随被选中的那个选项提交
                let note = q.options
                    .filter { $0.textInput != nil && codes.contains($0.code) }
                    .compactMap { draft.texts["\(q.questionId).\($0.code)"] }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                return SurveyAnswer(questionID: q.questionId, state: .answered,
                                    optionCodes: codes.sorted(), textValue: note, answeredAt: stamp)
            }
            if q.type == "text",
               let t = draft.texts[q.questionId]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !t.isEmpty {
                return SurveyAnswer(questionID: q.questionId, state: .answered,
                                    optionCodes: nil, textValue: t, answeredAt: stamp)
            }
            if draft.skipped.contains(q.questionId) {
                return SurveyAnswer(questionID: q.questionId, state: .skipped,
                                    optionCodes: nil, textValue: nil, answeredAt: stamp)
            }
            return SurveyAnswer(questionID: q.questionId, state: .notAnswered,
                                optionCodes: nil, textValue: nil, answeredAt: nil)
        }
    }
}

/// 国籍选择：平台提供的国家与地区列表，**名称按问卷语言本地化显示，保存的是固定的
/// ISO 3166-1 两位代码**（需求 U07）。可搜索、可多选。
/// 不按设备地区、界面语言或 IP 预先替用户选。
struct CountryPickerSheet: View {
    let language: String
    let selected: Set<String>
    let title: String
    let onToggle: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var chosen: Set<String>

    init(language: String, selected: Set<String>, title: String,
         onToggle: @escaping (String) -> Void) {
        self.language = language
        self.selected = selected
        self.title = title
        self.onToggle = onToggle
        _chosen = State(initialValue: selected)
    }

    static func name(for code: String, language: String) -> String {
        Locale(identifier: language == "zh" ? "zh-Hans" : language)
            .localizedString(forRegionCode: code) ?? code
    }

    private static func allCodes() -> [String] {
        Locale.Region.isoRegions
            .filter { $0.subRegions.isEmpty && $0.identifier.count == 2 }
            .map(\.identifier)
    }

    private var rows: [(code: String, name: String)] {
        let all = Self.allCodes()
            .map { (code: $0, name: Self.name(for: $0, language: language)) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(q)
            || $0.code.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(rows, id: \.code) { row in
                Button {
                    if chosen.contains(row.code) { chosen.remove(row.code) } else { chosen.insert(row.code) }
                    onToggle(row.code)
                } label: {
                    HStack {
                        Text(row.name).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if chosen.contains(row.code) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.primary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(chosen.contains(row.code) ? .isSelected : [])
                .accessibilityIdentifier("country.\(row.code)")
            }
            .searchable(text: $query, prompt: title)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("settings_done", comment: "")) { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
    }
}
