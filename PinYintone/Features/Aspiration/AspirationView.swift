import SwiftUI

/// 送气练习（/p/ /t/ /k/ · 吹散蒲公英）。补充练习，不进入本轮研究的声调主分析。
/// 展示词条 → 500ms 噪声校准 → 对麦克风送气 → 振幅超阈 → 蒲公英飞散 → 达标。
///
/// 达标后只在页面里给一行状态和「下一个词」，**不弹全屏庆祝遮罩**。
struct AspirationView: View {
    @StateObject private var vm = AspirationViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                if let lex = vm.currentLexeme {
                    LexemeCardView(lexeme: lex)
                    Text(NSLocalizedString("aspiration_prompt", comment: ""))
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !vm.calibrated {
                    ProgressView(NSLocalizedString("aspiration_calibrating", comment: ""))
                        .frame(minHeight: 220)
                } else {
                    DandelionView(triggerRate: vm.triggerRate)
                        .frame(width: 200, height: 200)

                    // 送气强度
                    Text("\(Int((vm.triggerRate * 100).rounded()))%")
                        .font(.title.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)

                    ProgressView(value: Double(vm.triggerRate))
                        .tint(Theme.primary)
                        .animation(reduceMotion ? nil : .easeInOut, value: vm.triggerRate)

                    // 是否达标同时用图标和文字表达
                    StatusLabel(kind: vm.triggered ? .success : .neutral, text: statusText)
                }

                // 技术性失败（麦克风起不来 / 没录上）。与送气是否达标严格区分。
                if let hint = vm.retryHint {
                    StatusLabel(kind: .warning, text: hint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if vm.passed {
                    Button {
                        vm.loadNextLexeme()
                    } label: {
                        Label(NSLocalizedString("tone_next_word", comment: ""),
                              systemImage: "forward.end")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("aspiration.next")
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("stage1_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if vm.currentLexeme == nil { vm.loadNextLexeme() }
        }
        .onDisappear { vm.stop() }
    }

    private var statusText: String {
        vm.triggered
            ? NSLocalizedString("aspiration_success", comment: "")
            : NSLocalizedString("aspiration_keep_going", comment: "")
    }
}
