import Foundation

/// 语料库加载器：从 Bundle 读取 Resources/Corpus/lexemes.json，按关卡类别顺序循环取词。
///
/// 实验可比性（关卡 2）：
/// - 关卡 2 走 `toneOrder` 定义的**固定词序**，A/B 两组完全一致，
///   避免"练了哪些词"成为混杂变量淹没反馈方式的效应。
/// - 游标写入 UserDefaults（每台设备每次安装独立），冷启动续接不归零，
///   避免每个 session 都从第一个词重新开始导致首词被过度采样。
final class CorpusLoader {
    static let shared = CorpusLoader()

    private let lexemes: [Lexeme]
    private var cursors: [LexemeCategory: Int] = [:]

    /// 关卡 2 固定词序（由易到难）。两组学习者按同一顺序推进。
    /// 依据：1+1 平调基准 → 轻声 → 单向调 → 调域跨度大的 1+3 →
    /// 先降后升的 3+1 / 4+3 → 全去声 4+4（最难，放最后避免开局劝退）。
    /// 未列入的 tone 词条按 JSON 原序追加在后，便于后续扩充语料。
    private static let toneOrder: [String] = [
        "yisheng", "canjia",              // 1+1 基准平调
        "xiuxi", "qingchu",               // 1+5 轻声
        "xiangxin",                       // 1+4
        "heshui", "shenti", "jingli",     // 1+3 调域跨度
        "zaocan",                         // 3+1
        "ziji",                           // 4+3
        "xianzai", "dianshi", "sushe", "hanzi",  // 4+4 全去声（最难）
    ]

    private init() {
        lexemes = Self.loadFromBundle()
        restoreCursors()
    }

    /// 全部词条
    func loadLexemes() -> [Lexeme] { lexemes }

    /// 指定类别的词条
    func lexemes(in category: LexemeCategory) -> [Lexeme] {
        lexemes.filter { $0.category == category }
    }

    /// 指定类别的**实际推进顺序**（关卡 2 为固定词序，其它类别为 JSON 原序）
    func orderedPool(category: LexemeCategory) -> [Lexeme] {
        let pool = lexemes.filter { $0.category == category }
        guard category == .tone else { return pool }
        var remaining = pool
        var ordered: [Lexeme] = []
        for id in Self.toneOrder {
            if let i = remaining.firstIndex(where: { $0.id == id }) {
                ordered.append(remaining.remove(at: i))
            }
        }
        return ordered + remaining   // 未列入固定序的新词追加在后
    }

    /// 按类别顺序循环返回下一词；该类别为空时返回占位词。
    /// 游标持久化，冷启动续接（见类型注释）。
    func nextLexeme(category: LexemeCategory) -> Lexeme {
        let pool = orderedPool(category: category)
        guard !pool.isEmpty else { return Self.placeholder(category) }
        let idx = (cursors[category] ?? 0) % pool.count
        setCursor(idx + 1, for: category)
        return pool[idx]
    }

    /// 当前游标在词表中的位置（1-based）与词表总数，供进度显示。
    func progress(category: LexemeCategory) -> (index: Int, total: Int) {
        let total = orderedPool(category: category).count
        guard total > 0 else { return (0, 0) }
        return (((cursors[category] ?? 0) % total) + 1, total)
    }

    /// 按 id 查找
    func lexeme(id: String) -> Lexeme? {
        lexemes.first { $0.id == id }
    }

    /// 重置某类别游标（仅调试/重新开始实验用）
    func resetCursor(category: LexemeCategory) {
        setCursor(0, for: category)
    }

    // MARK: - 游标持久化

    /// UserDefaults 本身即"每设备每安装"独立，无需再拼 deviceID；
    /// 且 CorpusLoader 非 MainActor，避免触碰 UIDevice。
    private static func cursorKey(_ category: LexemeCategory) -> String {
        "pt_corpus_cursor_\(category.rawValue)"
    }

    private func restoreCursors() {
        for category in [LexemeCategory.tone, .aspiration] {
            let saved = UserDefaults.standard.integer(forKey: Self.cursorKey(category))
            if saved > 0 { cursors[category] = saved }
        }
    }

    private func setCursor(_ value: Int, for category: LexemeCategory) {
        cursors[category] = value
        UserDefaults.standard.set(value, forKey: Self.cursorKey(category))
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
