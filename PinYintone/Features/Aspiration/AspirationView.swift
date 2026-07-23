import SwiftUI

/// 关卡 1：送气训练（/p/ /t/ /k/ · 吹散蒲公英）。
/// 展示词条 → 500ms 噪声校准 → 对麦克风送气 → 振幅超阈 → 蒲公英飞散 → 通关。
struct AspirationView: View {
    @StateObject private var vm = AspirationViewModel()

    var body: some View {
        VStack(spacing: 24) {
            if let lex = vm.currentLexeme {
                LexemeCardView(lexeme: lex)
                Text(NSLocalizedString("aspiration_prompt", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !vm.calibrated {
                ProgressView(NSLocalizedString("aspiration_calibrating", comment: ""))
                    .frame(maxHeight: .infinity)
            } else {
                DandelionView(triggerRate: vm.triggerRate)
                    .frame(width: 220, height: 220)

                // 送气强度（百分比，用户友好）
                Text("\(Int((vm.triggerRate * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(vm.triggered ? .green : .orange)

                ProgressView(value: Double(vm.triggerRate))
                    .tint(vm.triggered ? .green : .orange)
                    .animation(.easeInOut, value: vm.triggerRate)
                    .padding(.horizontal)

                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(vm.triggered ? .green : .primary)

                Spacer()
            }
        }
        .padding()
        .navigationTitle(NSLocalizedString("stage1_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if vm.currentLexeme == nil { vm.loadNextLexeme() }
        }
        .onDisappear { vm.stop() }
        .overlay {
            if vm.passed {
                // 关卡 1 沿用单按钮形态（不传 onNext）：行为与此前一致
                FeedbackOverlayView(
                    result: FeedbackResult(dtwScore: 0, grade: .excellent,
                                           attemptNumber: 1, segments: []),
                    onRetry: { vm.loadNextLexeme() }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: vm.passed)
    }

    private var statusText: String {
        vm.triggered
            ? NSLocalizedString("aspiration_success", comment: "")
            : NSLocalizedString("aspiration_keep_going", comment: "")
    }
}
