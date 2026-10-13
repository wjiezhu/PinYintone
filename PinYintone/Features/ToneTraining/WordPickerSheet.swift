import SwiftUI

/// 选词（需求 U04）：固定词库的**词卡网格**，可按汉字或拼音搜索。
///
/// 只是把词库摆出来——没有推荐、没有排序算法、不显示练过几次或得了多少分。
/// 当前词有描边和对勾；选中即返回练习页，反馈模式保持不变。
/// 放大文字时改成一列，长译文照常换行。
struct WordPickerSheet: View {
    let currentID: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
            ScrollView {
                if words.isEmpty {
                    Text(NSLocalizedString("word_picker_empty", comment: ""))
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.pageMargin)
                } else {
                    grid
                        .padding(.horizontal, Theme.pageMargin)
                        .padding(.vertical, Theme.Space.l)
                }
            }
            .background(Theme.background)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: NSLocalizedString("word_picker_search", comment: ""))
            .navigationTitle(NSLocalizedString("word_picker_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common_close", comment: "")) { dismiss() }
                }
            }
        }
        .tint(Theme.primary)
    }

    private var grid: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        let all = words
        let rows = stride(from: 0, to: all.count, by: columns).map {
            Array(all[$0..<min($0 + columns, all.count)])
        }
        return VStack(spacing: Theme.Space.m) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                // 同一行两张卡等高
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(row) { lexeme in
                        Button {
                            onSelect(lexeme.id)
                            dismiss()
                        } label: {
                            WordTile(lexeme: lexeme, language: localization.language,
                                     isCurrent: lexeme.id == currentID)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(lexeme.id == currentID ? .isSelected : [])
                        .accessibilityIdentifier("word.\(lexeme.id)")
                    }
                    if row.count < columns {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 词条行：汉字、拼音、释义。首页词表与选词列表共用。
struct WordRow: View {
    let lexeme: Lexeme
    let language: String
    var isCurrent = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    Text(lexeme.hanzi)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    ToneGlyphRow(tones: lexeme.tones)
                }
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
                    .foregroundStyle(Theme.primary)
                    .accessibilityLabel(NSLocalizedString("word_current", comment: ""))
            }
        }
        .frame(minHeight: Theme.minTap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
