import AVFoundation
import SwiftUI
import UIKit

/// 声调练习（需求 U03 / R06）。
///
/// 自上而下的顺序固定：标题与选词入口 → 汉字、拼音、释义 → 颜色/曲线切换 →
/// 反馈图 → 本次结果与建议/回听 → 底部固定操作栏。
///
/// **底部操作栏钉在安全区之上**：听示范 · 录音/停止 · 下一词。待录、录音、分析、
/// 反馈、失败任何状态下三个位置都不动——「录完 → 看反馈 → 再录」是最高频的路径，
/// 手指不该每次重新找按钮。内容多了由上面的区域滚动，操作栏始终够得着。
///
/// 打开就是普通练习：有反馈、可选词、可换词、可重录、随时返回。
/// 自测在右上角的次级菜单里，由学习者主动开始，可随时取消。
struct ToneTrainingView: View {
    /// 从首页词表点进来时要直接练的词；nil 表示接着上次停留的词
    var initialLexemeID: String?

    @StateObject private var vm = ToneTrainingViewModel()
    /// 反馈显示模式（学习者自选，非实验分组）。与设置页共用同一个键。
    @AppStorage(FeedbackStyle.storageKey) private var feedbackStyle: FeedbackStyle = .dynamicF0
    @ObservedObject private var recordings = LearnerRecordingStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var showWordPicker = false
    @State private var showMicExplanation = false
    @State private var didApplyInitialWord = false

    var body: some View {
        Group {
            if vm.mode == .selfTest {
                SelfTestContent(vm: vm)
            } else if let lexeme = vm.currentLexeme {
                practiceContent(lexeme)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        // 放大文字时导航栏放不下长标题（系统会截成「…」），标题改放到内容区顶部并允许换行
        .navigationTitle(typeSize.isAccessibilitySize ? "" : pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 自测中不能用系统返回直接离开：先明确退出自测，回到普通练习
        .navigationBarBackButtonHidden(vm.mode == .selfTest)
        .toolbar { toolbar }
        // 练习页底部只留一条操作栏：主导航在这一页收起，返回首页后恢复。
        // 两条栏叠在一起时，录音键离拇指更远，也分不清哪条是哪条。
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if !didApplyInitialWord, let initialLexemeID {
                didApplyInitialWord = true
                ToneSequencer.shared.select(lexemeID: initialLexemeID)
            }
            if vm.currentLexeme == nil { vm.loadCurrent() }
            // 上次达到条件但没来得及邀请的使用后问卷（如 App 被杀），现在补上
            vm.presentPostInvitationIfDue()
        }
        .onDisappear { vm.leavePage() }
        .onChange(of: vm.stage) { _, stage in announce(stage) }
        .sheet(isPresented: $showWordPicker) {
            WordPickerSheet(currentID: vm.currentLexeme?.id) { vm.select(lexemeID: $0) }
        }
        .sheet(isPresented: $vm.showAdvice) {
            PracticeAdviceView(advice: vm.currentAdvice,
                               onPlaySample: { vm.playSample() },
                               onReplayOwn: { vm.replayOwnRecording() },
                               onPracticeAgain: { vm.clearFeedbackForRetry() })
        }
        // 使用后问卷：只在用户结束当前反馈之后出现。下拉关掉 = 稍后填写，不是拒绝。
        .sheet(item: $vm.postSurveyInvitation, onDismiss: {
            if SurveyCenter.record(SurveyCenter.postKey)?.status == .invited {
                SurveyCenter.deferSurvey(SurveyCenter.postKey)
            }
        }) { _ in
            PostSurveyInvitationSheet { vm.postSurveyInvitation = nil }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMicExplanation) { micExplanation }
    }

    private var pageTitle: String {
        NSLocalizedString(vm.mode == .selfTest ? "self_test_title" : "stage2_title", comment: "")
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if vm.mode == .selfTest {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("self_test_exit", comment: "")) { vm.endSelfTest() }
                    .accessibilityIdentifier("selfTest.exit")
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showWordPicker = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel(NSLocalizedString("word_picker_title", comment: ""))
                .accessibilityIdentifier("practice.wordPicker")
                // 录音或分析期间禁止换词
                .disabled(vm.isBusy)

                // 自测放在次级菜单里，不占首屏主按钮的位置
                Menu {
                    Button {
                        vm.beginSelfTest()
                    } label: {
                        Label(NSLocalizedString("self_test_start", comment: ""),
                              systemImage: "checklist")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(NSLocalizedString("common_more", comment: ""))
                .accessibilityIdentifier("practice.more")
                .disabled(vm.isBusy)
            }
        }
    }

    // MARK: - 普通练习

    private func practiceContent(_ lexeme: Lexeme) -> some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                if typeSize.isAccessibilitySize {
                    Text(pageTitle)
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                LexemeCardView(lexeme: lexeme)
                    .padding(.top, Theme.Space.m)
                    .padding(.bottom, Theme.Space.xs)

                modeSwitcher

                chart(lexeme)

                statusArea
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, Theme.Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var modeSwitcher: some View {
        Picker(NSLocalizedString("settings_feedback_style", comment: ""),
               selection: $feedbackStyle) {
            // 顺序固定为「颜色 · 曲线」
            ForEach([FeedbackStyle.staticColor, .dynamicF0], id: \.self) { style in
                Text(NSLocalizedString(style.localizationKey, comment: "")).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: feedbackStyle) { old, new in
            // 只在用户实际切换时记一次，视图重绘不记
            vm.logFeedbackModeChanged(from: old, to: new)
        }
        // 录音、分析中换模式会让「看到的线 ≠ 评分的线」，直接禁掉
        .disabled(vm.isBusy)
        .accessibilityIdentifier("practice.modeSwitcher")
    }

    /// 反馈图。高度固定，内容随模式与状态替换，外部布局不受影响。
    private func chart(_ lexeme: Lexeme) -> some View {
        Group {
            switch feedbackStyle {
            case .staticColor:
                ModeA_StaticView(lexeme: lexeme, studentF0: vm.studentF0,
                                 referenceF0: vm.displayReference)
            case .dynamicF0:
                ModeB_F0WaveformView(lexeme: lexeme, studentF0: vm.studentF0,
                                     referenceF0: vm.displayReference)
            }
        }
        .frame(height: Theme.chartHeight)
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 0)
        .accessibilityIdentifier("practice.chart")
    }

    // MARK: - 状态与结果

    /// 图下方的一块：按录音状态机显示「现在是什么情况、下一步做什么」。
    /// 技术失败用琥珀色加图标，说明可以怎么办——**不显示成低分**。
    @ViewBuilder
    private var statusArea: some View {
        switch vm.stage {
        case .preparing:
            statusLine("tone_stage_preparing", spinning: true)
        case .ready:
            statusLine("tone_stage_ready", icon: "mic")
        case .recording:
            statusLine("tone_stage_recording", icon: "record.circle.fill",
                       iconColor: Theme.recording, textColor: Theme.textPrimary)
        case .analyzing:
            statusLine("tone_stage_analyzing", spinning: true)
        case .feedback:
            if let result = vm.feedbackResult { resultBlock(result) }
        case .failed(let failure):
            failureBlock(failure)
        case .selfTestRecorded:
            EmptyView()
        }
    }

    /// 一行状态：图标（或转圈）+ 一句话，居中
    private func statusLine(_ key: String, icon: String? = nil, spinning: Bool = false,
                            iconColor: Color = Theme.textSecondary,
                            textColor: Color = Theme.textSecondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            if spinning {
                ProgressView()
            } else if let icon {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }
            Text(NSLocalizedString(key, comment: ""))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.s)
    }

    /// 本次结果。只说这一次录音的情况，不称「能力评分」，也不做音节级判断。
    private func resultBlock(_ result: FeedbackResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(key: "result_title")
                // 一行放得下就左右排；文字放大后放不下，改成上下排（不缩字、不断词）
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Theme.Space.m) {
                        resultStatus(result)
                        Spacer(minLength: 0)
                        resultScore(result)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        resultStatus(result)
                        resultScore(result)
                    }
                }
                // 换词提示：连续几次没通过时给一个出口，不是评价
                if vm.consecutiveFailures >= vm.skipHintThreshold {
                    Text(NSLocalizedString("feedback_skip_hint", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)

            RowDivider()

            // 三个后续动作等宽排开，位置固定；没有可回听的录音时回听一格不出现
            HStack(spacing: 0) {
                resultAction(icon: "arrow.counterclockwise", caption: "result_try_again",
                             label: "result_try_again", id: "practice.tryAgain") {
                    vm.clearFeedbackForRetry()
                }
                if recordings.hasRecording {
                    columnDivider
                    resultAction(icon: vm.playing == .ownRecording ? "stop.fill" : "play.fill",
                                 caption: vm.playing == .ownRecording ? "bar_stop" : "replay_short",
                                 label: vm.playing == .ownRecording
                                     ? "replay_stop" : "replay_own_recording",
                                 id: "practice.replay") {
                        vm.replayOwnRecording()
                    }
                }
                columnDivider
                // 建议：点了才打开，不自动弹出
                resultAction(icon: "lightbulb", caption: "advice_short",
                             label: "advice_open", id: "practice.advice") {
                    vm.openAdvice()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.divider))
        // 结果**真正出现在屏幕上**才算「已显示」：研究记录的结果显示时间、
        // feedback_displayed 事件、合格练习计次都从这里触发，按尝试编号去重。
        .onAppear { vm.feedbackDidAppear() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice.result")
    }

    private func resultStatus(_ result: FeedbackResult) -> some View {
        StatusLabel(kind: result.grade == .fail ? .neutral : .success,
                    text: NSLocalizedString(result.grade == .fail
                                            ? "result_not_passed" : "result_passed", comment: ""),
                    prominent: true)
    }

    private func resultScore(_ result: FeedbackResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(result.score)")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text("/ 100")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .fixedSize()
        // 数字的书写方向不随界面方向镜像
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: NSLocalizedString("result_score_a11y", comment: ""),
                                   result.score))
    }

    private var columnDivider: some View {
        Theme.divider.frame(width: 1)
    }

    /// 结果区的一个动作：图标在上、一个短词在下。完整说明给 VoiceOver。
    private func resultAction(icon: String, caption: String, label: String, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .frame(height: 22)
                    .accessibilityHidden(true)
                Text(NSLocalizedString(caption, comment: ""))
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, Theme.Space.m)
            .padding(.horizontal, Theme.Space.xs)
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString(label, comment: ""))
        .accessibilityIdentifier(id)
    }

    private func failureBlock(_ failure: ToneTrainingViewModel.Failure) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            StatusLabel(kind: .warning,
                        text: NSLocalizedString(failure.messageKey, comment: ""))
            if failure.offersSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label(NSLocalizedString("onboarding_open_settings", comment: ""),
                          systemImage: "gearshape")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("practice.openSettings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        .background(Theme.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius)
            .strokeBorder(Theme.warning.opacity(0.4)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice.failure")
    }

    // MARK: - 底部操作栏（三个位置固定）

    /// 听示范 · 录音/停止 · 下一词。三格等宽，录音键恒在正中。
    /// 用不上的格子（自测里没有示范和换词）留空占位，不移除——否则录音键会横跳。
    private var actionBar: some View {
        PracticeActionBar {
            if vm.mode == .practice {
                BarButton(icon: vm.playing == .sample ? "stop.fill" : "speaker.wave.2.fill",
                          caption: NSLocalizedString(vm.playing == .sample ? "bar_stop" : "bar_listen",
                                                     comment: ""),
                          label: NSLocalizedString(vm.playing == .sample
                                                   ? "sample_stop" : "play_sample", comment: ""),
                          id: "practice.listen") { vm.playSample() }
                    // 录音时不能再播放示范
                    .disabled(vm.isBusy)
            } else {
                BarPlaceholder()
            }
        } center: {
            RecordButton(isRecording: vm.isRecording,
                         isEnabled: vm.canRecord && !vm.selfTestFinished) {
                handleRecordTap()
            }
            .accessibilityValue(stageDescription)
        } trailing: {
            if vm.mode == .practice {
                BarButton(icon: "forward.end.fill",
                          caption: NSLocalizedString("bar_next", comment: ""),
                          label: NSLocalizedString("tone_next_word", comment: ""),
                          id: "practice.next") { vm.loadNext() }
                    // 录音时不能切词
                    .disabled(vm.isBusy)
            } else {
                BarPlaceholder()
            }
        }
    }

    /// 录音键的无障碍取值：当前处在流程的哪一步。VoiceOver 聚焦到按钮时会读出来。
    private var stageDescription: String {
        switch vm.stage {
        case .preparing: return NSLocalizedString("tone_stage_preparing", comment: "")
        case .ready: return ""
        case .recording: return NSLocalizedString("tone_stage_recording", comment: "")
        case .analyzing: return NSLocalizedString("tone_stage_analyzing", comment: "")
        case .feedback: return NSLocalizedString("result_title", comment: "")
        case .selfTestRecorded: return NSLocalizedString("self_test_recorded", comment: "")
        case .failed(let failure): return NSLocalizedString(failure.messageKey, comment: "")
        }
    }

    private func handleRecordTap() {
        // 麦克风权限在首次实际录音前申请。先用所选语言说明用途，再弹系统授权框。
        if !vm.isRecording, !RecordingSourceFactory.isSynthetic,
           AVAudioApplication.shared.recordPermission == .undetermined {
            showMicExplanation = true
            return
        }
        vm.toggleRecording()
    }

    private var micExplanation: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    IconTile(systemName: "mic.fill", size: 56)
                    Text(NSLocalizedString("onboarding_mic_body", comment: ""))
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(NSLocalizedString("onboarding_mic_privacy", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                Button {
                    showMicExplanation = false
                    vm.startRecording()      // 触发系统授权框；同意后直接开始录
                } label: {
                    Text(NSLocalizedString("onboarding_mic_allow", comment: ""))
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(Theme.pageMargin)
                .accessibilityIdentifier("mic.allow")
            }
            .navigationTitle(NSLocalizedString("mic_explain_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { showMicExplanation = false }
                }
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.medium, .large])
    }

    // MARK: - 无障碍

    /// 状态变化时给 VoiceOver 一句提示：看不见屏幕的人也要知道录音开始了、结果出来了
    private func announce(_ stage: ToneTrainingViewModel.Stage) {
        let key: String?
        switch stage {
        case .recording: key = "tone_stage_recording"
        case .analyzing: key = "tone_stage_analyzing"
        case .feedback:
            key = vm.feedbackResult?.grade == .fail ? "result_not_passed" : "result_passed"
        case .failed(let failure): key = failure.messageKey
        case .selfTestRecorded: key = "self_test_recorded"
        case .preparing, .ready: key = nil
        }
        guard let key else { return }
        UIAccessibility.post(notification: .announcement,
                             argument: NSLocalizedString(key, comment: ""))
    }
}

// MARK: - 自测

/// 自测（需求 U04）。中性的「自测 · 第 x / n 词」，只推进录音。
///
/// **不呈现任何评价**：没有分数、等级、评价颜色、参考曲线、示范播放、建议或积分。
/// 完成页只陈述「录完了」这一事实和一个返回练习的入口，不给能力结论。
/// 技术失败可以重录，不算完成这一题、也不记零分。
struct SelfTestContent: View {
    @ObservedObject var vm: ToneTrainingViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                if vm.selfTestFinished {
                    finished
                } else if let lexeme = vm.currentLexeme, let session = vm.selfTest {
                    progress(session)
                        .padding(.top, Theme.Space.l)

                    LexemeCardView(lexeme: lexeme)

                    neutralStatus
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// 进度：一行「第 x / n 词」加一排小格。用中性灰，不用任何评价色——
    /// 它只表示录到第几个，不表示录得怎么样。
    private func progress(_ session: SelfTestSession) -> some View {
        VStack(spacing: Theme.Space.s) {
            Text(String(format: NSLocalizedString("self_test_progress", comment: ""),
                        session.position, session.total))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("selfTest.progress")
            HStack(spacing: Theme.Space.xs) {
                ForEach(0..<max(session.total, 1), id: \.self) { index in
                    Capsule()
                        .fill(index < session.position ? Theme.textSecondary : Theme.divider)
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: 220)
            .accessibilityHidden(true)
        }
    }

    /// 只说录音处于什么状态，绝不透露任何音高或评价信息
    @ViewBuilder
    private var neutralStatus: some View {
        VStack(spacing: Theme.Space.m) {
            switch vm.stage {
            case .failed(let failure):
                StatusLabel(kind: .warning,
                            text: NSLocalizedString(failure.messageKey, comment: ""))
                if failure.offersSettings {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label(NSLocalizedString("onboarding_open_settings", comment: ""),
                              systemImage: "gearshape")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            default:
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(height: 44)
                    .accessibilityHidden(true)
                Text(NSLocalizedString(statusKey, comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .surfaceCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selfTest.status")
    }

    private var icon: String {
        switch vm.stage {
        case .recording: return "waveform"
        case .selfTestRecorded: return "checkmark.circle"
        default: return "mic"
        }
    }

    private var statusKey: String {
        switch vm.stage {
        case .preparing: return "tone_stage_preparing"
        case .recording: return "tone_stage_recording"
        case .analyzing: return "self_test_saving"
        case .selfTestRecorded: return "self_test_recorded"
        default: return "self_test_ready"
        }
    }

    private var finished: some View {
        VStack(spacing: Theme.Space.l) {
            IconTile(systemName: "checkmark", size: 56)
                .padding(.top, Theme.Space.xl)
            Text(NSLocalizedString("self_test_done_title", comment: ""))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("self_test_done_body", comment: ""))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                vm.endSelfTest()
            } label: {
                Text(NSLocalizedString("self_test_back_to_practice", comment: ""))
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("selfTest.back")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selfTest.finished")
    }
}
