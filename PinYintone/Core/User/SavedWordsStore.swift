import Combine
import Foundation

/// 收藏词条本地存储（UserDefaults 持久化）。新收藏置顶，自动去重。
@MainActor
final class SavedWordsStore: ObservableObject {
    static let shared = SavedWordsStore()

    @Published private(set) var words: [SavedWord] = []

    private let defaults: UserDefaults
    private let storageKey = "pt_saved_words"
    private let pinyinConverter = PinyinConverter()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func contains(_ word: String) -> Bool {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.contains { $0.word == key }
    }

    func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !contains(trimmed) else { return }
        let entry = SavedWord(
            id: UUID(),
            word: trimmed,
            pinyin: pinyinConverter.pinyin(for: trimmed),
            tones: pinyinConverter.toneSequence(for: trimmed),
            savedAt: Date()
        )
        words.insert(entry, at: 0)   // 新收藏置顶
        persist()
    }

    func removeWord(_ word: String) {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines)
        words.removeAll { $0.word == key }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        words = words.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        persist()
    }

    /// 收藏 / 取消收藏切换
    func toggle(_ word: String) {
        contains(word) ? removeWord(word) : add(word)
    }

    // MARK: - 私有

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedWord].self, from: data) else { return }
        words = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(words) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
