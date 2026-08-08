import SwiftUI

/// 关卡 2：声调训练（受试内 A/B 实验作用域）。
/// 训练期按**词的子集 + 被试平衡顺序**逐词渲染模式 A（静态颜色）或 B（动态 F0）；
/// 前测/后测为**裸测**——录音并后台评分上报，但不显示任何反馈（分数/等级/可视化）。
struct ToneTrainingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ToneTrainingViewModel()

    var body: some View {
        VStack(spacing: 16) {
            if let lexeme = vm.currentLexeme {
                LexemeCardView(lexeme: lexeme)

                // 听样例读音
                Button {
                    vm.playSample()
                } label: {
                    Label(NSLocalizedString("play_sample", comment: ""), systemImage: "speaker.wave.2.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(vm.isRecording)

                // ── 反馈区 ──────────────────────────────
                if vm.showsFeedback {
                    // 训练期：按词呈现 A（静态色块）或 B（动态曲线）。
                    // 参照曲线用 vm.displayReference：录音中固定为锁定值（所见即所评）。
                    Group {
                        switch vm.currentPresentationMode {
                        case .staticColor:
                            ModeA_StaticView(lexeme: lexeme,
                                             studentF0: vm.studentF0,
                                             referenceF0: vm.displayReference)
                        case .dynamicF0, .none:
                            ModeB_F0WaveformView(lexeme: lexeme,
                                                 studentF0: vm.studentF0,
                                                 referenceF0: vm.displayReference)
                        }
                    }
                    .frame(height: 200)
                    .overlay {
                        // 参照加载中：轻量提示，此时录音按钮禁用（P0-4）
                        if !vm.isReferenceReady && !vm.isRecording {
                            ProgressView()
                                .padding(10)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .animation(.easeInOut(duration: 0.1), value: vm.studentF0.count)

                    if let result = vm.feedbackResult {
                        DTWScoreView(result: result)
                    }
                } else {
                    // 前测/后测：裸测——不显示任何 F0/颜色/分数反馈
                    assessmentPlaceholder
                        .frame(height: 200)
                }

                // 技术性失败提示（没录好），与发音评价区分开
                if let hint = vm.retryHint {
                    Label(hint, systemImage: "mic.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                RecordButton(isRecording: vm.isRecording) {
                    vm.isRecording ? vm.stopRecordingAndEvaluate() : vm.startRecording()
                }
                // 参照未就绪不给录，堵住"看到的线≠评分的线"的竞态窗口
                .disabled(!vm.isReferenceReady && !vm.isRecording)
            } else {
                ProgressView()
            }
        }
        .padding()
        .navigationTitle(NSLocalizedString("stage2_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.loadNext()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(vm.isRecording)
            }
        }
        .overlay {
            // 仅训练期弹反馈层；前后测裸测不显示（P0-6）
            if vm.showsFeedback, let result = vm.feedbackResult, !vm.isRecording {
                // 推进不再以通关为前提：由学习者选择再试或换词（P0-1）
                FeedbackOverlayView(
                    result: result,
                    showSkipHint: vm.consecutiveFailures >= vm.skipHintThreshold,
                    onRetry: { vm.feedbackResult = nil },
                    onNext: { vm.feedbackResult = nil; vm.loadNext() }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: vm.feedbackResult?.attemptNumber)
        .onAppear { if vm.currentLexeme == nil { vm.loadNext() } }
    }

    /// 裸测占位：只提示读词，不给任何反馈
    private var assessmentPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("assessment_read_aloud", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
