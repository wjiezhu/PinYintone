import SwiftUI

/// 关卡 3 入口：粘贴/输入中文文本 → 自动分词 → 进入分词编辑页。
struct FreeTextInputView: View {
    @State private var rawText: String = ""
    @State private var tokens: [String] = []
    @State private var showEditor: Bool = false

    private let tokenizer = ChineseTokenizer()
    private let maxChars = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(NSLocalizedString("freetext_input_hint", comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $rawText)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .onChange(of: rawText) { new in
                                if new.count > maxChars { rawText = String(new.prefix(maxChars)) }
                            }
                        if rawText.isEmpty {
                            Text(NSLocalizedString("freetext_placeholder", comment: ""))
                                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .surfaceCard(padding: Theme.Space.s)

                    Text("\(rawText.count) / \(maxChars)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }

                Button {
                    tokens = tokenizer.tokenize(rawText)
                    showEditor = !tokens.isEmpty
                } label: {
                    Text(NSLocalizedString("freetext_tokenize", comment: ""))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canTokenize)
                .accessibilityIdentifier("freeText.tokenize")
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
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
