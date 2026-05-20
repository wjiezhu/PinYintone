import Foundation

/// 语料库加载器：从 Bundle 读取 Resources/Corpus/lexemes.json，并提供顺序循环取词。
final class CorpusLoader {
    static let shared = CorpusLoader()

    private let lexemes: [Lexeme]
    private var cursor = 0

    private init() {
        lexemes = Self.loadFromBundle()
    }

    /// 全部词条
    func loadLexemes() -> [Lexeme] { lexemes }

    /// 顺序循环返回下一词；语料为空时返回占位词
    func nextLexeme() -> Lexeme {
        guard !lexemes.isEmpty else { return Self.placeholder }
        defer { cursor = (cursor + 1) % lexemes.count }
        return lexemes[cursor]
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

    private static let placeholder = Lexeme(
        id: "placeholder",
        hanzi: "你好",
        pinyin: "nǐ hǎo",
        tones: [3, 3],
        audioFilename: nil
    )
}
