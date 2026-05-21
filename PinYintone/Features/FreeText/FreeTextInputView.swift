import SwiftUI

/// 关卡 3 入口：粘贴/输入中文文本 → 自动分词 → 进入分词编辑页。
struct FreeTextInputView: View {
    @State private var rawText: String = ""
    @State private var tokens: [String] = []
    @State private var showEditor: Bool = false

    private let tokenizer = ChineseTokenizer()
    private let maxChars = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("freetext_input_hint", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $rawText)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: rawText) { _, new in
                        if new.count > maxChars { rawText = String(new.prefix(maxChars)) }
                    }
                if rawText.isEmpty {
                    Text(NSLocalizedString("freetext_placeholder", comment: ""))
                        .foregroundStyle(.tertiary)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Text("\(rawText.count) / \(maxChars)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                tokens = tokenizer.tokenize(rawText)
                showEditor = !tokens.isEmpty
            } label: {
                Text(NSLocalizedString("freetext_tokenize", comment: ""))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canTokenize ? Color.accentColor : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canTokenize)

            Spacer()
        }
        .padding(20)
        .navigationTitle(NSLocalizedString("stage3_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SavedWordsView()
                } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel(NSLocalizedString("saved_words_title", comment: ""))
            }
        }
        .navigationDestination(isPresented: $showEditor) {
            TokenEditorView(tokens: $tokens, originalText: rawText)
        }
    }

    private var canTokenize: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
