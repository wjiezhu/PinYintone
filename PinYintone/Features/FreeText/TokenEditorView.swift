import SwiftUI

/// 分词编辑页：FlowLayout 展示词条芯片，支持删除/新增，然后进入逐词练习。
struct TokenEditorView: View {
    @Binding var tokens: [String]
    let originalText: String

    @State private var newWord: String = ""
    private let pinyinConverter = PinyinConverter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(NSLocalizedString("freetext_edit_hint", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // 词条芯片流式布局
                FlowLayout(spacing: 10) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { idx, token in
                        TokenChipView(
                            token: token,
                            pinyin: pinyinConverter.pinyin(for: token),
                            onTap: {},
                            onDelete: { tokens.remove(at: idx) }
                        )
                    }
                }

                // 新增自定义词
                HStack {
                    TextField(NSLocalizedString("freetext_add_word", comment: ""), text: $newWord)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            tokens.append(trimmed)
                            newWord = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer(minLength: 12)

                NavigationLink {
                    FreeWordPracticeView(tokens: tokens, originalText: originalText)
                } label: {
                    Text(NSLocalizedString("freetext_start_practice", comment: ""))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(tokens.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(tokens.isEmpty)
            }
            .padding(20)
        }
        .navigationTitle(NSLocalizedString("freetext_edit_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
