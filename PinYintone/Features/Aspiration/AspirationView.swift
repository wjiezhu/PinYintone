import SwiftUI

/// 送气练习。补充练习，不进入本轮研究的声调主分析。
///
/// 词分两类，方向相反：送气音（p / t / k）要爆破、吹散蒲公英；
/// 不送气音（b / d / g）不要爆破、蒲公英不动。
/// 点录音开始 → 500ms 噪声校准 → 念第一个字 → 再点一下停止 → 看结果。
struct AspirationView: View {
    @StateObject private var vm = AspirationViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                if let lex = vm.currentLexeme {
                    LexemeCardView(lexeme: lex)
                    if let target = lex.aspirationTarget {
                        targetInfo(target, lexeme: lex)
                    }
                }

                DandelionView(triggerRate: displayRate)
                    .frame(width: 200, height: 200)

                // 送气强度：录音中是当前值，停止后是这次的最高值（判定依据）
                Text("\(Int((displayRate * 100).rounded()))%")
                    .font(.title.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .environment(\.layoutDirection, .leftToRight)

                ProgressView(value: Double(displayRate))
                    .tint(Theme.primary)
                    .animation(reduceMotion ? nil : .easeInOut, value: displayRate)

                status
                    .frame(maxWidth: .infinity)

                // 技术性失败（麦克风起不来 / 没录上）。与发音结果严格区分。
                if let hint = vm.retryHint {
                    StatusLabel(kind: .warning, text: hint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: .infinity)
        }
        .bounceOnlyWhenScrollable()
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .navigationTitle(NSLocalizedString("stage1_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if vm.currentLexeme == nil { vm.loadNextLexeme() }
        }
        .onDisappear { vm.leavePage() }
    }

    private var displayRate: Float {
        vm.stage == .result ? vm.peakRate : vm.triggerRate
    }

    /// 这个词是送气还是不送气，以及这次该怎么念。类型用文字说明，不单靠颜色。
    private func targetInfo(_ target: AspirationTarget, lexeme: Lexeme) -> some View {
        let char = String(lexeme.hanzi.prefix(1))
        return VStack(spacing: Theme.Space.s) {
            Text(String(format: NSLocalizedString(
                target.aspirated ? "aspiration_tag_aspirated" : "aspiration_tag_unaspirated",
                comment: ""), target.initial))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.xs)
                .background(Theme.secondaryBackground)
                .clipShape(Capsule())
                .accessibilityIdentifier("aspiration.target")
            Text(String(format: NSLocalizedString(
                target.aspirated ? "aspiration_prompt_aspirated" : "aspiration_prompt_unaspirated",
                comment: ""), target.initial, char))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch vm.stage {
        case .idle:
            statusText("aspiration_ready")
        case .calibrating:
            ProgressView(NSLocalizedString("aspiration_calibrating", comment: ""))
        case .recording:
            statusText("aspiration_recording")
        case .result:
            // 是否通过同时用图标和文字表达
            StatusLabel(kind: vm.passed == true ? .success : .neutral, text: resultText)
                .accessibilityIdentifier("aspiration.result")
        }
    }

    private func statusText(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resultText: String {
        let key: String
        switch (vm.isAspirated, vm.passed == true) {
        case (true, true):   key = "aspiration_success"
        case (true, false):  key = "aspiration_keep_going"
        case (false, true):  key = "aspiration_unaspirated_success"
        case (false, false): key = "aspiration_unaspirated_too_strong"
        }
        return NSLocalizedString(key, comment: "")
    }

    /// 与声调练习同一套操作栏：录音键恒在正中，位置不动，点一下开始、再点一下停止。
    private var actionBar: some View {
        PracticeActionBar {
            BarPlaceholder()
        } center: {
            RecordButton(isRecording: vm.isActive) { vm.toggleRecording() }
        } trailing: {
            BarButton(icon: "forward.end",
                      caption: NSLocalizedString("bar_next", comment: ""),
                      label: NSLocalizedString("tone_next_word", comment: ""),
                      id: "aspiration.next") { vm.loadNextLexeme() }
                .disabled(vm.isActive)
        }
    }
}
