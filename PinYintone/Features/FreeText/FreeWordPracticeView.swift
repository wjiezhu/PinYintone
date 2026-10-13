import SwiftUI

/// 自由文本的逐词练习：当前词 + 拼音 + 曲线 + 本次结果。
///
/// 与声调练习页同一套版式与操作语义：底部操作栏钉死、录音键居中、
/// 点一下开始再点一下停止。左右两格是上一词 / 下一词。
/// 这里的声调是由文本**自动推定**的，未经教师核对，所以没有词条提示。
struct FreeWordPracticeView: View {
    let tokens: [String]
    var originalText: String = ""

    @StateObject private var vm = FreeWordPracticeViewModel()
    @ObservedObject private var savedWords = SavedWordsStore.shared
    @State private var currentIndex: Int = 0

    private let pinyinConverter = PinyinConverter()

    private var currentWord: String {
        tokens.indices.contains(currentIndex) ? tokens[currentIndex] : ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Text("\(currentIndex + 1) / \(tokens.count)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)

                VStack(spacing: Theme.Space.xs) {
                    Text(currentWord)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(pinyinConverter.pinyin(for: currentWord))
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .environment(\.layoutDirection, .leftToRight)

                FreeF0Canvas(studentF0: vm.studentF0,
                             idealToneShape: vm.idealShape,
                             tones: vm.currentTones)
                    .frame(height: Theme.chartHeight)

                // 技术性失败（录音起不来 / 没录上）。与发音结果严格区分，没有成绩。
                if let hint = vm.retryHint {
                    StatusLabel(kind: .warning, text: hint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result = vm.feedbackResult {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
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
                        }
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .navigationTitle(NSLocalizedString("stage3_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    vm.playSample()
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .accessibilityLabel(NSLocalizedString("play_sample", comment: ""))
                .disabled(vm.isRecording)

                Button {
                    savedWords.toggle(currentWord)
                } label: {
                    Image(systemName: savedWords.contains(currentWord) ? "bookmark.fill" : "bookmark")
                }
                .disabled(currentWord.isEmpty)
                .accessibilityLabel(NSLocalizedString("save_word", comment: ""))
            }
        }
        .onAppear {
            vm.originalText = originalText
            vm.prepare(word: currentWord)
        }
        // 录音评分完成后，若该词已收藏则记录练习进度（最佳分/次数）
        .onChange(of: vm.feedbackResult?.dtwScore) { _, newValue in
            if newValue != nil, let result = vm.feedbackResult {
                savedWords.recordPractice(word: currentWord, score: result.score)
            }
        }
    }

    /// 上一词 · 录音/停止 · 下一词。三格等宽，录音键恒在正中；左右顺序不随界面方向镜像。
    private var actionBar: some View {
        HStack(spacing: 0) {
            barButton(icon: "backward.end", label: "freetext_prev") { move(by: -1) }
                .disabled(currentIndex == 0 || vm.isRecording)
                .frame(maxWidth: .infinity)
            RecordButton(isRecording: vm.isRecording) {
                vm.toggleRecording(targetWord: currentWord)
            }
            .frame(maxWidth: .infinity)
            barButton(icon: "forward.end", label: "freetext_next") { move(by: 1) }
                .disabled(currentIndex >= tokens.count - 1 || vm.isRecording)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.xs)
        .background(.bar)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func barButton(icon: String, label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 56, height: Theme.minTap + 4)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(NSLocalizedString(label, comment: ""))
    }

    private func move(by delta: Int) {
        let next = currentIndex + delta
        guard tokens.indices.contains(next) else { return }
        currentIndex = next
        vm.prepare(word: tokens[next])
    }
}
