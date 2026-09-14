import SwiftUI

/// 问卷界面：**每屏一题**（需求 §3），允许跳过，允许整份谢绝。
///
/// 几条不能省的规则（问卷文档 §1、字典 §11）：
/// - 跳过与「没有困难」「从不」「未遇到问题」是**不同状态**，分别保存。
/// - 互斥选项（如「不愿回答」「目前没有明显困难」）与其余选项不能同选。
/// - 多选有上限时超出要拦住（PRE06 最多 2 项）。
/// - 「其他」被选中时可以填说明，但**不强制**。
/// - 自由文本一律提示不要填写可识别个人身份的信息。
struct SurveyFormView: View {
    let formKey: String
    let onFinish: (SurveyOutcome) -> Void

    @State private var form: SurveyForm?
    @State private var index = 0
    @State private var selections: [String: Set<String>] = [:]
    @State private var texts: [String: String] = [:]
    @State private var skipped: Set<String> = []
    @State private var startedAt: Date?
    @State private var limitWarning = false

    private var lang: String { LocalizationManager.shared.language }

    var body: some View {
        Group {
            if let form {
                content(form)
            } else {
                // 定义加载不出来时不要空白卡住：直接放行，不阻断使用
                Color.clear.onAppear { onFinish(declined()) }
            }
        }
        .onAppear {
            form = SurveyFormLoader.load(formKey)
            startedAt = Date()
        }
    }

    @ViewBuilder
    private func content(_ form: SurveyForm) -> some View {
        let q = form.questions[index]
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: Double(index + 1), total: Double(form.questions.count))

            Text(q.question[lang] ?? q.question["zh"] ?? q.questionId)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let hint = q.hint?[lang] {
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(q.options, id: \.code) { opt in
                        optionRow(q, opt)
                    }
                    if q.type == "text" { textField(q) }
                }
            }

            if limitWarning, let maxN = q.maxSelections {
                Text(String(format: NSLocalizedString("survey_max_selections", comment: ""), maxN))
                    .font(.footnote).foregroundStyle(.orange)
            }

            Spacer(minLength: 0)
            navigationBar(form, q)
        }
        .padding(20)
    }

    @ViewBuilder
    private func optionRow(_ q: SurveyForm.Question, _ opt: SurveyForm.Option) -> some View {
        let chosen = selections[q.questionId]?.contains(opt.code) == true
        Button {
            toggle(q, opt)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: chosen
                      ? (q.type == "single" ? "largecircle.fill.circle" : "checkmark.square.fill")
                      : (q.type == "single" ? "circle" : "square"))
                    .foregroundStyle(chosen ? Color.accentColor : .secondary)
                Text(opt.label[lang] ?? opt.label["zh"] ?? opt.code)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        // 选中「其他」才展示补充输入框，且不强制填写
        if chosen, opt.textInput != nil {
            TextField(NSLocalizedString("survey_other_hint", comment: ""),
                      text: binding(for: "\(q.questionId).\(opt.code)"))
                .textFieldStyle(.roundedBorder)
                .padding(.leading, 28)
        }
    }

    @ViewBuilder
    private func textField(_ q: SurveyForm.Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: binding(for: q.questionId))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
            Text(NSLocalizedString("survey_privacy_hint", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func navigationBar(_ form: SurveyForm, _ q: SurveyForm.Question) -> some View {
        HStack {
            if index > 0 {
                Button(NSLocalizedString("survey_previous", comment: "")) { index -= 1 }
            }
            Spacer()
            Button(NSLocalizedString("survey_skip", comment: "")) {
                skipped.insert(q.questionId)
                selections[q.questionId] = nil
                advance(form)
            }
            .foregroundStyle(.secondary)
            Button(index == form.questions.count - 1
                   ? NSLocalizedString("survey_submit", comment: "")
                   : NSLocalizedString("survey_next", comment: "")) {
                advance(form)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 作答逻辑

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { texts[key] ?? "" }, set: { texts[key] = $0 })
    }

    private func toggle(_ q: SurveyForm.Question, _ opt: SurveyForm.Option) {
        skipped.remove(q.questionId)
        limitWarning = false
        var current = selections[q.questionId] ?? []
        let exclusives = Set(q.options.filter { $0.exclusive == true }.map(\.code))

        if q.type == "single" {
            current = [opt.code]
        } else if current.contains(opt.code) {
            current.remove(opt.code)
        } else if exclusives.contains(opt.code) {
            // 互斥选项：清掉其余全部
            current = [opt.code]
        } else {
            // 选普通项时先清掉互斥项
            current.subtract(exclusives)
            if let maxN = q.maxSelections, current.count >= maxN {
                limitWarning = true
                return
            }
            current.insert(opt.code)
        }
        selections[q.questionId] = current.isEmpty ? nil : current
    }

    private func advance(_ form: SurveyForm) {
        if index < form.questions.count - 1 {
            index += 1
            limitWarning = false
        } else {
            onFinish(build(form))
        }
    }

    private func build(_ form: SurveyForm) -> SurveyOutcome {
        let now = Date()
        let answers = form.questions.map { q -> SurveyAnswer in
            if let codes = selections[q.questionId], !codes.isEmpty {
                return SurveyAnswer(questionID: q.questionId, state: .answered,
                                    optionCodes: Array(codes).sorted(),
                                    textValue: texts[q.questionId], answeredAt: now)
            }
            if let t = texts[q.questionId], !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return SurveyAnswer(questionID: q.questionId, state: .answered,
                                    optionCodes: nil, textValue: t, answeredAt: now)
            }
            if skipped.contains(q.questionId) {
                return SurveyAnswer(questionID: q.questionId, state: .skipped,
                                    optionCodes: nil, textValue: nil, answeredAt: now)
            }
            return SurveyAnswer(questionID: q.questionId, state: .notAnswered,
                                optionCodes: nil, textValue: nil, answeredAt: nil)
        }
        let anyAnswered = answers.contains { $0.state == .answered }
        let allAnswered = answers.allSatisfy { $0.state == .answered }
        return SurveyOutcome(formKey: form.formKey, formVersion: form.formVersion,
                             translationVersion: form.translationVersion, language: lang,
                             answers: answers,
                             status: !anyAnswered ? "declined" : (allAnswered ? "complete" : "partial"),
                             startedAt: startedAt, submittedAt: now)
    }

    private func declined() -> SurveyOutcome {
        SurveyOutcome(formKey: formKey, formVersion: "unknown", translationVersion: "unknown",
                      language: lang, answers: [], status: "declined",
                      startedAt: startedAt, submittedAt: Date())
    }
}
