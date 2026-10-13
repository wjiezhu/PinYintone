import SwiftUI

/// 分词编辑页：FlowLayout 展示词条芯片，支持删除/新增，然后进入逐词练习。
struct TokenEditorView: View {
    @Binding var tokens: [String]
    let originalText: String

    @State private var newWord: String = ""
    private let pinyinConverter = PinyinConverter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(NSLocalizedString("freetext_edit_hint", comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 词条芯片流式布局
                FlowLayout(spacing: Theme.Space.s) {
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
                HStack(spacing: Theme.Space.s) {
                    TextField(NSLocalizedString("freetext_add_word", comment: ""), text: $newWord)
                        .frame(minHeight: Theme.minTap)
                        .surfaceCard(padding: Theme.Space.m)
                    Button {
                        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            tokens.append(trimmed)
                            newWord = ""
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: Theme.minTap, height: Theme.minTap)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(NSLocalizedString("freetext_add_word", comment: ""))
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer(minLength: 12)

                NavigationLink {
                    FreeWordPracticeView(tokens: tokens, originalText: originalText)
                } label: {
                    Text(NSLocalizedString("freetext_start_practice", comment: ""))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(tokens.isEmpty)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
        }
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("freetext_edit_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
