import Foundation

final class CorpusLoader {
    static let shared = CorpusLoader()
    private init() {}

    /// 从 Bundle 加载 Resources/Corpus/lexemes.json（20 词语料库）
    func loadLexemes() -> [Lexeme] {
        fatalError("TODO: 实现")
    }
}
