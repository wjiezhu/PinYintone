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

    /// 训练词固定顺序（A/B 子集按调型交替）。使每次练习都覆盖 A、B 两组，
    /// 且两子集在时间上均衡分布，不受"练了哪些词"混杂。测试词不在此列
    /// （P1-5#2：前后测词不进训练池）。
    private static let trainingOrder: [String] = [
        "kafei", "jintian",       // 1+1
        "jiating", "zhongwen",    // 1+2
        "qianbi", "shenti",       // 1+3
        "xuexi", "yinhang",       // 2+2
        "niunai", "cidian",       // 2+3
        "shoubiao", "shuiguo",    // 3+3
        "mianbao", "yisheng",     // 4+1 / 1+1（见词表脚注②对称性待定）
        "qiche", "jiaoshi",       // 4+1 / 4+4
    ]

    /// 测试词固定顺序（前测与后测同题同序，共 10 词）。
    private static let testOrder: [String] = [
        "gongsi", "zhongguo", "laoshi", "shijian", "pingguo",
        "keyi", "dianhua", "shangke", "hanyu", "xiexie",
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

    /// 指定类别的**实际推进顺序**。
    /// 关卡 2（tone）只返回**训练词**（A+B，排除测试词），按 trainingOrder 固定序；
    /// 其它类别为 JSON 原序。
    func orderedPool(category: LexemeCategory) -> [Lexeme] {
        guard category == .tone else {
            return lexemes.filter { $0.category == category }
        }
        return ordered(ids: Self.trainingOrder,
                       from: lexemes.filter { $0.subset == .trainingA || $0.subset == .trainingB })
    }

    /// 测试词（前后测），固定顺序共 10 词。供前测/后测流程使用。
    func testWords() -> [Lexeme] {
        ordered(ids: Self.testOrder, from: lexemes.filter { $0.subset == .test })
    }

    /// 某训练子集（A 或 B）的词，用于受试内按词分配呈现方式。
    func trainingWords(subset: LexemeSubset) -> [Lexeme] {
        lexemes.filter { $0.subset == subset }
    }

    /// 按给定 id 顺序排列；未列入的追加在后（便于后续扩充）
    private func ordered(ids: [String], from pool: [Lexeme]) -> [Lexeme] {
        var remaining = pool
        var out: [Lexeme] = []
        for id in ids {
            if let i = remaining.firstIndex(where: { $0.id == id }) {
                out.append(remaining.remove(at: i))
            }
        }
        return out + remaining
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
            subset: nil,
            focus: "",
            french: "Bonjour",
            darija: "Salam (سلام)",
            audioFilename: nil
        )
    }
}
