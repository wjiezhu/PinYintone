import Foundation

/// 汉字转拼音（CFStringTransform）+ 声调序列提取
struct PinyinConverter {

    /// 汉字转带声调拼音；withTones=false 时去掉变音符
    /// 示例：「今天」→ "jīn tiān"
    func pinyin(for hanzi: String, withTones: Bool = true) -> String {
        fatalError("TODO: 实现 — kCFStringTransformMandarinLatin + StripDiacritics")
    }

    /// 提取声调序列（1–4，轻声=5）
    /// 示例：「今天」→ [1, 1]
    func toneSequence(for hanzi: String) -> [Int] {
        fatalError("TODO: 实现")
    }

    /// 从单个拼音音节中检测声调（通过变音符 Unicode 码位）
    private func detectTone(syllable: String) -> Int {
        fatalError("TODO: 实现 — āēīōūǖ=1 / áéíóúǘ=2 / ǎěǐǒǔǚ=3 / àèìòùǜ=4 / else=5")
    }
}
