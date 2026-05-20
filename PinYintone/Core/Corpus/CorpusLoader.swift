import Foundation

/// 语料库加载器：从 Bundle 读取 Resources/Corpus/lexemes.json，按关卡类别顺序循环取词。
final class CorpusLoader {
    static let shared = CorpusLoader()

    private let lexemes: [Lexeme]
    private var cursors: [LexemeCategory: Int] = [:]

    private init() {
        lexemes = Self.loadFromBundle()
    }

    /// 全部词条
    func loadLexemes() -> [Lexeme] { lexemes }

    /// 指定类别的词条
    func lexemes(in category: LexemeCategory) -> [Lexeme] {
        lexemes.filter { $0.category == category }
    }

    /// 按类别顺序循环返回下一词；该类别为空时返回占位词
    func nextLexeme(category: LexemeCategory) -> Lexeme {
        let pool = lexemes.filter { $0.category == category }
        guard !pool.isEmpty else { return Self.placeholder(category) }
        let idx = (cursors[category] ?? 0) % pool.count
        cursors[category] = idx + 1
        return pool[idx]
    }

    /// 按 id 查找
    func lexeme(id: String) -> Lexeme? {
        lexemes.first { $0.id == id }
    }

    // MARK: - 私有

    private static func loadFromBundle() -> [Lexeme] {
        guard let url = Bundle.main.url(forResource: "lexemes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Lexeme].self, from: data)
        else { return [] }
        return decoded
    }

    private static func placeholder(_ category: LexemeCategory) -> Lexeme {
        Lexeme(
            id: "placeholder",
            hanzi: "你好",
            pinyin: "nǐ hǎo",
            tones: [3, 3],
            category: category,
            focus: "",
            french: "Bonjour",
            darija: "Salam (سلام)",
            audioFilename: nil
        )
    }
}
