import SwiftUI

/// 我的词条：查看本地收藏的练习词，点击可再次练习，左滑删除。
struct SavedWordsView: View {
    @ObservedObject private var store = SavedWordsStore.shared

    private let toneColors: [Color] = [.green, .blue, .orange, .red]

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
                    }
                    .onDelete { store.remove(atOffsets: $0) }
                }
            }
        }
        .navigationTitle(NSLocalizedString("saved_words_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.words.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }

    private func row(_ entry: SavedWord) -> some View {
        HStack(spacing: 12) {
            Text(entry.word)
                .font(.title3.weight(.medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.pinyin)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(Array(entry.tones.enumerated()), id: \.offset) { _, tone in
                        Text("\(tone)")
                            .font(.caption2.bold())
                            .frame(width: 18, height: 18)
                            .background(color(for: tone).opacity(0.18))
                            .foregroundStyle(color(for: tone))
                            .clipShape(Circle())
                    }
                }
            }
            Spacer()

            // 练习进度：最佳得分 + 次数
            if let best = entry.bestScore {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(best)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(scoreColor(best))
                        Text("/100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(format: NSLocalizedString("saved_words_practice_count", comment: ""),
                                entry.practiceCount))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...:  return .green
        case 75..<90: return .mint
        case 60..<75: return .orange
        default:      return .red
        }
    }

    private func color(for tone: Int) -> Color {
        (1...4).contains(tone) ? toneColors[tone - 1] : .gray
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("saved_words_empty", comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
