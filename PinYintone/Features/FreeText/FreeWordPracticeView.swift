import SwiftUI

/// 逐词练习界面：当前词 + 拼音 + 实时 F0 可视化 + 上/下一词导航。
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
        VStack(spacing: 16) {
            // 进度
            ProgressView(value: Double(currentIndex + 1), total: Double(max(tokens.count, 1)))
                .tint(.purple)
            Text("\(currentIndex + 1) / \(tokens.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 当前词
            VStack(spacing: 6) {
                Text(currentWord)
                    .font(.system(size: 44, weight: .bold))
                Text(pinyinConverter.pinyin(for: currentWord))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            // 实时 F0 画布
            FreeF0Canvas(studentF0: vm.studentF0,
                         idealToneShape: vm.idealShape,
                         tones: vm.currentTones)
                .frame(height: 200)
                .animation(.easeInOut(duration: 0.1), value: vm.studentF0.count)

            // 百分制评分（录音结束后）
            if let result = vm.feedbackResult {
                DTWScoreView(result: result)
                    .transition(.opacity)
            }

            Spacer()

            RecordButton(isRecording: vm.isRecording) {
                vm.toggleRecording(targetWord: currentWord)
            }

            // 上/下一词
            HStack {
                Button {
                    move(by: -1)
                } label: {
                    Label(NSLocalizedString("freetext_prev", comment: ""), systemImage: "chevron.left")
                }
                .disabled(currentIndex == 0 || vm.isRecording)

                Spacer()

                Button {
                    move(by: 1)
                } label: {
                    Label(NSLocalizedString("freetext_next", comment: ""), systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(currentIndex >= tokens.count - 1 || vm.isRecording)
            }
            .padding(.horizontal)
        }
        .padding()
        .navigationTitle(NSLocalizedString("stage3_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
    }

    private func move(by delta: Int) {
        let next = currentIndex + delta
        guard tokens.indices.contains(next) else { return }
        currentIndex = next
        vm.prepare(word: tokens[next])
    }
}
