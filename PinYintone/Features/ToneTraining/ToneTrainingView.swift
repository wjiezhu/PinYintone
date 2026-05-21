import SwiftUI

/// 关卡 2：声调训练（A/B 实验作用域，20 词语料库）。
/// 按 AppState.group 渲染模式 A（静态颜色）或模式 B（动态 F0 轨迹）；两组通关标准相同（DTW ≤ 0.5）。
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

                // ── A/B 分组视觉反馈分支 ──────────────────
                Group {
                    switch appState.group {
                    case .staticColor:
                        ModeA_StaticView(
                            lexeme: lexeme,
                            studentF0: vm.studentF0,
                            referenceF0: vm.referenceF0
                        )
                    case .dynamicF0:
                        ModeB_F0WaveformView(
                            lexeme: lexeme,
                            studentF0: vm.studentF0,
                            referenceF0: vm.referenceF0
                        )
                    }
                }
                .frame(height: 200)
                .animation(.easeInOut(duration: 0.1), value: vm.studentF0.count)

                if let result = vm.feedbackResult {
                    DTWScoreView(result: result)
                }

                Spacer()

                RecordButton(isRecording: vm.isRecording) {
                    vm.isRecording ? vm.stopRecordingAndEvaluate() : vm.startRecording()
                }
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
            if let result = vm.feedbackResult, !vm.isRecording {
                FeedbackOverlayView(result: result) {
                    vm.feedbackResult = nil
                    if result.grade != .fail { vm.loadNext() }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: vm.feedbackResult?.attemptNumber)
        .onAppear { if vm.currentLexeme == nil { vm.loadNext() } }
    }
}
