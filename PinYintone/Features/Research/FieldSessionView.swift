import SwiftUI

/// 现场实测里不显示练习界面的那几页：说明页、段落之间、完成页，以及前测 / 后测本身
/// （与自测同一个裸测页面）。训练段用普通练习的界面，由 `ToneTrainingView` 负责。
///
/// 前测与后测**不呈现任何评价**：没有分数、等级、颜色、曲线、示范或建议，
/// 段落之间也不透露前测「做得怎么样」。完成页只陈述做完了这一事实。
struct FieldSessionContent: View {
    @ObservedObject var vm: ToneTrainingViewModel

    var body: some View {
        if let field = vm.field {
            if vm.currentLexeme != nil, field.isBareTest {
                SelfTestContent(vm: vm)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        if !field.started {
                            intro(field)
                        } else if field.isComplete {
                            finished
                        } else if field.stepFinished {
                            between(field)
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.vertical, Theme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .bounceOnlyWhenScrollable()
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 说明页

    private func intro(_ field: FieldSession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            IconTile(systemName: "list.number", size: 56)
            Text(NSLocalizedString("field_intro_title", comment: ""))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            stepRow(1, String(format: NSLocalizedString("field_intro_pretest", comment: ""),
                              field.testWords.count))
            stepRow(2, String(format: NSLocalizedString("field_intro_training", comment: ""),
                              field.trainingWords.count, field.validAttemptsPerWord))
            stepRow(3, String(format: NSLocalizedString("field_intro_posttest", comment: ""),
                              field.testWords.count))
            Text(NSLocalizedString("field_intro_note", comment: ""))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            primary("field_start", id: "field.start") { vm.continueFieldSession() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.intro")
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text("\(n)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.primary)
                .frame(minWidth: 20)
                .environment(\.layoutDirection, .leftToRight)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 段落之间

    /// 只说「这一段做完了，下一段是什么」，不透露这一段的任何结果
    private func between(_ field: FieldSession) -> some View {
        let next = field.step.next
        let (title, body): (String, String) = {
            switch next {
            case .training:
                return (NSLocalizedString("field_pretest_done", comment: ""),
                        String(format: NSLocalizedString("field_next_training", comment: ""),
                               field.trainingWords.count, field.validAttemptsPerWord))
            default:
                return (NSLocalizedString("field_training_done", comment: ""),
                        String(format: NSLocalizedString("field_next_posttest", comment: ""),
                               field.testWords.count))
            }
        }()
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            IconTile(systemName: "checkmark", size: 56)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            primary("field_continue", id: "field.continue") { vm.continueFieldSession() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.between")
    }

    // MARK: - 完成页

    private var finished: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            IconTile(systemName: "checkmark", size: 56)
            Text(NSLocalizedString("field_done_title", comment: ""))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(NSLocalizedString("field_done_body", comment: ""))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            primary("field_back_to_practice", id: "field.back") { vm.endFieldSession() }
        }
        // 做完才邀请使用后问卷；只邀请一次
        .onAppear { vm.offerPostSurveyAfterFieldSession() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field.finished")
    }

    private func primary(_ key: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(NSLocalizedString(key, comment: ""))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier(id)
    }
}

/// 实测训练段的进度：第几个词、这个词已练几次。中性灰，不用评价色。
struct FieldTrainingHeader: View {
    let field: FieldSession

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(String(format: NSLocalizedString("field_training_progress", comment: ""),
                        field.position, field.total))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Text(String(format: NSLocalizedString("field_training_count", comment: ""),
                        min(field.validCount, field.validAttemptsPerWord),
                        field.validAttemptsPerWord))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("field.trainingProgress")
    }
}
