import SwiftUI

/// 关卡 2：声调训练。
///
/// 版式（「词卡 + 教练卡」方案）：屏幕自上而下只有一条阅读线——
/// **我在哪 → 念什么 → 怎么显示 → 结果 → 下一步**，底部三格操作栏钉死。
///
/// 关键不变式：**反馈出现时录音键一毫米都不动**。
/// 反馈区高度固定，录音键锚在底部操作栏中格，所以「录完 → 看反馈 → 再录」
/// 这条最高频的路径上，手指不需要重新找位置（档案 §4.2：按钮位置语义稳定）。
///
/// 三阶段（档案 §3.1）：
/// - `pretest` / `posttest`：固定测试词集，录完只显示中性的"已记录"，
///   **不显示分数、等级、颜色或曲线**，随后自动进入下一题；走完显示阶段完成。
/// - `training`：按学习者自选的显示模式渲染反馈，并给出一条行动提示。
struct ToneTrainingView: View {
    @StateObject private var vm = ToneTrainingViewModel()
    /// 反馈显示模式（学习者自选，非实验分组）。与设置页共用同一个键，切换即时生效。
    @AppStorage(FeedbackStyle.storageKey) private var feedbackStyle: FeedbackStyle = .dynamicF0

    /// 反馈区固定高度。反馈出没都在这块里发生，外面的东西一律不位移。
    private let feedbackSlotHeight: CGFloat = 200

    /// 前置问卷是否该挡在练习之前。
    /// 已开始过练习就不再当作「前置」——错过该时点不补录（问卷 §3）。
    private var shouldShowPreSurvey: Bool {
        ResearchEventLog.shared.isCollecting
            && ResearchSurveyTrigger.shared.shouldInvitePre
    }

    @State private var preSurveyDone = false

    var body: some View {
        Group {
            // 前置问卷挡在首次练习之前（需求 §3）。允许跳过与整份谢绝，
            // 答完或谢绝后直接进练习，不重复打扰。
            if shouldShowPreSurvey && !preSurveyDone {
                SurveyFormView(formKey: "tone_needs_v1") { outcome in
                    ResearchSurveyTrigger.shared.markPreInvited()
                    Task {
                        await SurveyUploader.shared.upload(
                            outcome,
                            timingClass: ResearchSurveyTrigger.shared.preTimingClass)
                        preSurveyDone = true
                    }
                }
            } else if let lexeme = vm.currentLexeme {
                trainingBody(lexeme)
            } else if vm.isPhaseComplete {
                PhaseCompleteView(phase: vm.phase)
                    .padding()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(NSLocalizedString("stage2_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(duration: 0.3), value: vm.feedbackResult?.attemptNumber)
        .onAppear { vm.loadCurrent() }
        // 使用后问卷在**本次结果页操作结束后**才弹，不遮挡尚未查看的反馈或回听。
        // 用 sheet 而非整页替换：用户可以下拉关掉、稍后再填。
        .sheet(isPresented: $vm.shouldShowPostSurvey) {
            SurveyFormView(formKey: "usability_short_v1") { outcome in
                ResearchSurveyTrigger.shared.markPostInvited()
                Task {
                    await SurveyUploader.shared.upload(outcome, timingClass: "after_practice")
                    vm.shouldShowPostSurvey = false
                }
            }
        }
    }

    // MARK: - 主体

    private func trainingBody(_ lexeme: Lexeme) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    PhaseBannerView(phase: vm.phase, progress: vm.progress)

                    LexemeCardView(lexeme: lexeme)

                    // 模式切换紧贴反馈区上沿：换的是哪一块，控件就压在哪一块头上，
                    // 不用去设置页翻。裸测不显示反馈，整条隐藏（留着只会让人去点）。
                    if vm.phase.showsFeedback {
                        modeSwitcher
                    }

                    feedbackSlot(lexeme)

                    // 分数只在训练阶段出现；裸测阶段任何评价性 UI 都不得渲染
                    if vm.phase.showsFeedback, let result = vm.feedbackResult {
                        DTWScoreView(result: result)
                    }

                    notices

                    // 训练阶段解锁后测后给出入口；不自动跳转，由学习者/研究者决定何时开始
                    if vm.phase == .training, vm.isPosttestUnlocked {
                        Button {
                            vm.beginPosttest()
                        } label: {
                            Label(NSLocalizedString("phase_start_posttest", comment: ""),
                                  systemImage: "flag.checkered")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isRecording)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            actionBar
        }
    }

    /// 结果状态 + 建议入口。状态只说通关与否，**不做任何音节级判断**。
    @ViewBuilder
    private func adviceEntry(_ result: FeedbackResult) -> some View {
        HStack(spacing: 10) {
            Label(NSLocalizedString(result.grade == .fail ? "result_not_passed" : "result_passed",
                                    comment: ""),
                  systemImage: result.grade == .fail ? "arrow.counterclockwise.circle" : "checkmark.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(result.grade == .fail ? .orange : .green)
            Spacer()
            Button(NSLocalizedString("advice_open", comment: "")) {
                vm.openAdvice()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 2)
        .sheet(isPresented: $vm.showAdvice) {
            PracticeAdviceView(advice: vm.currentAdvice,
                               onPlaySample: { vm.playSample() },
                               onReplayOwn: { vm.replayOwnRecording() },
                               onPracticeAgain: { vm.clearFeedbackForRetry() })
        }
    }

    // MARK: - 模式切换

    private var modeSwitcher: some View {
        Picker(NSLocalizedString("settings_feedback_style", comment: ""),
               selection: $feedbackStyle) {
            ForEach(FeedbackStyle.allCases, id: \.self) { style in
                Text(NSLocalizedString(style.localizationKey, comment: "")).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: feedbackStyle) { old, new in
            // 字典 §8：feedback_mode_changed 记**用户主动切换**，需带 from/to。
            // 颜色与曲线自选切换是使用行为，不得编码成随机分组（字典 §8 末注）。
            vm.logFeedbackModeChanged(from: old, to: new)
        }
        // 录音中换模式会让"看到的线 ≠ 评分的线"，直接禁掉
        .disabled(vm.isRecording)
    }

    // MARK: - 反馈区（固定高度，内部换内容）

    /// 反馈区。**高度恒为 `feedbackSlotHeight`**，内容随状态替换，外部布局不受影响。
    /// - 训练阶段未出分：整块交给所选显示模式（目标声调 / 目标轨迹）。
    /// - 训练阶段已出分：教练卡占上半，显示模式缩为下半的辅助图。
    /// - 裸测阶段：只显示录音状态，两种模式都不渲染。
    @ViewBuilder
    private func feedbackSlot(_ lexeme: Lexeme) -> some View {
        Group {
            if vm.phase.showsFeedback {
                if let result = vm.feedbackResult, !vm.isRecording {
                    VStack(spacing: 10) {
                        // 需求 §5：建议**点击后查看，不强制弹出**。
                        // 这里只保留一行非诊断性的状态——否则学习者看到「不通关」
                        // 却完全没有下一步线索；具体建议全部在面板里。
                        adviceEntry(result)
                        replayButton
                        modeView(lexeme)
                            .frame(maxHeight: .infinity)
                    }
                } else {
                    modeView(lexeme)
                }
            } else {
                BlindRecordingView(isRecording: vm.isRecording)
            }
        }
        .frame(height: feedbackSlotHeight)
    }

    /// 学习者自选的两种显示方式。参照曲线用 `vm.displayReference`：
    /// 录音中固定为锁定值，保证一次录音全程参照线不变（所见即所评）。
    @ViewBuilder
    private func modeView(_ lexeme: Lexeme) -> some View {
        switch feedbackStyle {
        case .staticColor:
            ModeA_StaticView(lexeme: lexeme,
                             studentF0: vm.studentF0,
                             referenceF0: vm.displayReference)
        case .dynamicF0:
            ModeB_F0WaveformView(lexeme: lexeme,
                                 studentF0: vm.studentF0,
                                 referenceF0: vm.displayReference)
        }
    }

    // MARK: - 回执与技术失败提示

    @ViewBuilder
    private var notices: some View {
        // 测试阶段的中性回执：只说"录到了"，不含任何评价
        if let notice = vm.assessmentNotice {
            Label(notice, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        // 技术性失败（没录好 / 引擎起不来）与发音评价严格区分；三阶段都要显示。
        // 这是 §4.2「录音质量不达标只提示重录」的落点，不得静默。
        if let hint = vm.retryHint {
            Label(hint, systemImage: "mic.slash")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    /// 回听本次录音。
    ///
    /// **不放进底部操作栏**：那三格是钉死的（听样例 · 录音 · 下一题），
    /// 录音键恒在正中，加第四格会破坏该不变量（档案 §4.2）。
    /// 放在结果区，与"刚录完这一条"的语境相连。
    @ViewBuilder
    private var replayButton: some View {
        if vm.canReplay {
            Button {
                vm.replayOwnRecording()
            } label: {
                Label(NSLocalizedString("replay_own_recording", comment: ""),
                      systemImage: "arrow.counterclockwise.circle")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .disabled(vm.isRecording)
        }
    }

    // MARK: - 底部操作栏（三格钉死）

    /// 听样例 · 录音 · 下一题。三格宽度固定，录音键恒在正中，
    /// 任何阶段、任何模式、有没有反馈都不改变位置与语义（档案 §4.2）。
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                vm.playSample()
            } label: {
                Label(NSLocalizedString("play_sample", comment: ""),
                      systemImage: "speaker.wave.2.fill")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(vm.isRecording)

            RecordButton(isRecording: vm.isRecording) {
                vm.isRecording ? vm.stopRecordingAndEvaluate() : vm.startRecording()
            }
            // 参照未就绪不给录，堵住"看到的线≠评分的线"的竞态窗口
            .disabled(!vm.isReferenceReady && !vm.isRecording)

            Button {
                vm.feedbackResult = nil
                vm.loadNext()
            } label: {
                Label(NSLocalizedString("tone_next_word", comment: ""),
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            // 测试阶段必须按固定顺序走完、录完自动推进，不提供手动跳过。
            // 但格子保留（禁用而非移除），否则录音键会左右横跳。
            .disabled(vm.isRecording || !vm.phase.showsFeedback)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}
