import SwiftUI

/// 我的词条：查看本地收藏的练习词，点击可再次练习，左滑删除。
struct SavedWordsView: View {
    @ObservedObject private var store = SavedWordsStore.shared

    var body: some View {
        Group {
            if store.words.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.words) { entry in
                        NavigationLink {
                            FreeWordPracticeView(tokens: [entry.word])
                        } label: {
                            row(entry)
                        }
                        .listRowBackground(Theme.surface)
                    }
                    .onDelete { store.remove(atOffsets: $0) }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("saved_words_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.words.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }

    private func row(_ entry: SavedWord) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    Text(entry.word)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    ToneGlyphRow(tones: entry.tones)
                }
                Text(entry.pinyin)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .environment(\.layoutDirection, .leftToRight)
            Spacer(minLength: Theme.Space.s)

            // 练过几次。只陈述次数，不给分数着色——这是练习日志，不是成绩单
            if entry.practiceCount > 0 {
                Text(String(format: NSLocalizedString("saved_words_practice_count", comment: ""),
                            entry.practiceCount))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minHeight: Theme.minTap)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "bookmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(NSLocalizedString("saved_words_empty", comment: ""))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
