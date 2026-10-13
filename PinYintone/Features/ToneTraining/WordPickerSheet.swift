import SwiftUI

/// 选词（需求 U04）：固定词库的列表，可按汉字或拼音搜索。
///
/// 只是把词库列出来——没有推荐、没有排序算法、不显示练过几次或得了多少分。
/// 选中即返回练习页，反馈模式保持不变。
struct WordPickerSheet: View {
    let currentID: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var query = ""

    private var words: [Lexeme] {
        let all = CorpusLoader.shared.orderedPool(category: .tone)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let plain = Self.stripTones(q)
        return all.filter {
            $0.hanzi.contains(q)
                || Self.stripTones($0.pinyin).contains(plain)
                || $0.id.localizedCaseInsensitiveContains(plain)
        }
    }

    /// 去掉声调符号与空格后比较：输入 "heshui" 能找到 "hē shuǐ"
    static func stripTones(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
    }

    var body: some View {
        NavigationStack {
            List {
                if words.isEmpty {
                    Text(NSLocalizedString("word_picker_empty", comment: ""))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(words) { lexeme in
                        Button {
                            onSelect(lexeme.id)
                            dismiss()
                        } label: {
                            WordRow(lexeme: lexeme, language: localization.language,
                                    isCurrent: lexeme.id == currentID)
                        }
                        .accessibilityIdentifier("word.\(lexeme.id)")
                    }
                }
            }
            .searchable(text: $query,
                        prompt: NSLocalizedString("word_picker_search", comment: ""))
            .navigationTitle(NSLocalizedString("word_picker_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common_close", comment: "")) { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// 词条行：汉字、拼音、释义。首页词表与选词列表共用。
struct WordRow: View {
    let lexeme: Lexeme
    let language: String
    var isCurrent = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lexeme.hanzi)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(lexeme.pinyin)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            // 中文词与拼音的字序不随界面方向镜像
            .environment(\.layoutDirection, .leftToRight)
            Spacer(minLength: Theme.Space.s)
            Text(lexeme.glosses(for: language).primary)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(NSLocalizedString("word_current", comment: ""))
            }
        }
        .frame(minHeight: Theme.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
