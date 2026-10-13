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
        .navigationTitle(NSLocalizedString(vm.mode == .selfTest ? "self_test_title" : "stage2_title",
                                           comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        // 自测中不能用系统返回直接离开：先明确退出自测，回到普通练习
        .navigationBarBackButtonHidden(vm.mode == .selfTest)
        .toolbar { toolbar }
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
                LexemeCardView(lexeme: lexeme)
                    .padding(.top, Theme.Space.s)

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
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityIdentifier("practice.chart")
    }

    // MARK: - 状态与结果

    /// 图下方的一块：按录音状态机显示「现在是什么情况、下一步做什么」。
    /// 技术失败用琥珀色加图标，说明可以怎么办——**不显示成低分**。
    @ViewBuilder
    private var statusArea: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            switch vm.stage {
            case .preparing:
                progressLine("tone_stage_preparing")
            case .ready:
                hintLine("tone_stage_ready")
            case .recording:
                hintLine("tone_stage_recording")
            case .analyzing:
                progressLine("tone_stage_analyzing")
            case .feedback:
                if let result = vm.feedbackResult { resultBlock(result) }
            case .failed(let failure):
                failureBlock(failure)
            case .selfTestRecorded:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("practice.status")
    }

    private func progressLine(_ key: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            ProgressView()
            Text(NSLocalizedString(key, comment: ""))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func hintLine(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.body)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 本次结果。只说这一次录音的情况，不称「能力评分」，也不做音节级判断。
    private func resultBlock(_ result: FeedbackResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(key: "result_title")
            HStack(alignment: .firstTextBaseline) {
                StatusLabel(kind: result.grade == .fail ? .neutral : .success,
                            text: NSLocalizedString(result.grade == .fail
                                                    ? "result_not_passed" : "result_passed",
                                                    comment: ""))
                Spacer()
                Text("\(result.score) / 100")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel(String(format: NSLocalizedString("result_score_a11y",
                                                                         comment: ""), result.score))
            }
            // 换词提示：连续几次没通过时给一个出口，不是评价
            if vm.consecutiveFailures >= vm.skipHintThreshold {
                Text(NSLocalizedString("tone_skip_hint", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Space.s) {
                Button {
                    vm.clearFeedbackForRetry()
                } label: {
                    Label(NSLocalizedString("result_try_again", comment: ""),
                          systemImage: "arrow.counterclockwise")
                }
                .accessibilityIdentifier("practice.tryAgain")

                if recordings.hasRecording {
                    Button {
                        vm.replayOwnRecording()
                    } label: {
                        Label(NSLocalizedString(vm.playing == .ownRecording
                                                ? "replay_stop" : "replay_own_recording",
                                                comment: ""),
                              systemImage: vm.playing == .ownRecording
                                  ? "stop.circle" : "play.circle")
                    }
                    .accessibilityIdentifier("practice.replay")
                }

                // 建议：点了才打开，不自动弹出
                Button {
                    vm.openAdvice()
                } label: {
                    Label(NSLocalizedString("advice_open", comment: ""),
                          systemImage: "lightbulb")
                }
                .accessibilityIdentifier("practice.advice")
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        // 结果**真正出现在屏幕上**才算「已显示」：研究记录的结果显示时间、
        // feedback_displayed 事件、合格练习计次都从这里触发，按尝试编号去重。
        .onAppear { vm.feedbackDidAppear() }
        .accessibilityIdentifier("practice.result")
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
                .buttonStyle(.bordered)
                .accessibilityIdentifier("practice.openSettings")
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityIdentifier("practice.failure")
    }

    // MARK: - 底部操作栏（三个位置固定）

    /// 听示范 · 录音/停止 · 下一词。三格等宽，录音键恒在正中。
    /// 用不上的格子（自测里没有示范和换词）留空占位，不移除——否则录音键会横跳。
    private var actionBar: some View {
        HStack(spacing: 0) {
            Group {
                if vm.mode == .practice {
                    barButton(icon: vm.playing == .sample ? "stop.circle" : "speaker.wave.2",
                              label: vm.playing == .sample ? "sample_stop" : "play_sample",
                              id: "practice.listen") { vm.playSample() }
                        // 录音时不能再播放示范
                        .disabled(vm.isBusy)
                } else {
                    Color.clear.frame(height: Theme.minTap)
                }
            }
            .frame(maxWidth: .infinity)

            RecordButton(isRecording: vm.isRecording,
                         isEnabled: vm.canRecord && !vm.selfTestFinished) {
                handleRecordTap()
            }
            .frame(maxWidth: .infinity)

            Group {
                if vm.mode == .practice {
                    barButton(icon: "forward.end", label: "tone_next_word",
                              id: "practice.next") { vm.loadNext() }
                        // 录音时不能切词
                        .disabled(vm.isBusy)
                } else {
                    Color.clear.frame(height: Theme.minTap)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.xs)
        .frame(maxWidth: .infinity)
        .background(.bar)
        // 操作栏的左右顺序固定，不随界面方向镜像：示范在左、下一词在右
        .environment(\.layoutDirection, .leftToRight)
    }

    private func barButton(icon: String, label: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 56, height: Theme.minTap + 4)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(NSLocalizedString(label, comment: ""))
        .accessibilityIdentifier(id)
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
                    Image(systemName: "mic")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
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
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
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
                    Text(String(format: NSLocalizedString("self_test_progress", comment: ""),
                                session.position, session.total))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Theme.Space.l)
                        .accessibilityIdentifier("selfTest.progress")

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
                    .buttonStyle(.bordered)
                }
            default:
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text(NSLocalizedString(statusKey, comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
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
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
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
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("selfTest.back")
        }
        .accessibilityIdentifier("selfTest.finished")
    }
}
