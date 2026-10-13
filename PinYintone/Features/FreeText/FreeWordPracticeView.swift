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
    @ScaledMetric(relativeTo: .largeTitle) private var hanziSize: CGFloat = 40

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
                        .font(.system(size: hanziSize, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(pinyinConverter.pinyin(for: currentWord))
                        .font(.title3.weight(.medium))
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
                        HStack(alignment: .center, spacing: Theme.Space.m) {
                            StatusLabel(kind: result.grade == .fail ? .neutral : .success,
                                        text: NSLocalizedString(result.grade == .fail
                                                                ? "result_not_passed" : "result_passed",
                                                                comment: ""),
                                        prominent: true)
                            Spacer(minLength: 0)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(result.score)")
                                    .font(.title2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                                Text("/ 100")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(String(format: NSLocalizedString("result_score_a11y",
                                                                                 comment: ""),
                                                       result.score))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Space.m)
                    .overlay(alignment: .top) { RowDivider() }
                    .overlay(alignment: .bottom) { RowDivider() }
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
        PracticeActionBar {
            BarButton(icon: "backward.end",
                      caption: NSLocalizedString("bar_prev", comment: ""),
                      label: NSLocalizedString("freetext_prev", comment: ""),
                      id: "freeText.prev") { move(by: -1) }
                .disabled(currentIndex == 0 || vm.isRecording)
        } center: {
            RecordButton(isRecording: vm.isRecording) {
                vm.toggleRecording(targetWord: currentWord)
            }
        } trailing: {
            BarButton(icon: "forward.end",
                      caption: NSLocalizedString("bar_next", comment: ""),
                      label: NSLocalizedString("freetext_next", comment: ""),
                      id: "freeText.next") { move(by: 1) }
                .disabled(currentIndex >= tokens.count - 1 || vm.isRecording)
        }
    }

    private func move(by delta: Int) {
        let next = currentIndex + delta
        guard tokens.indices.contains(next) else { return }
        currentIndex = next
        vm.prepare(word: tokens[next])
    }
}
