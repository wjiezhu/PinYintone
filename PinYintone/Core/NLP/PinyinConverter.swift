import Foundation

/// 汉字转拼音（CFStringTransform）+ 声调序列提取，零第三方依赖。
struct PinyinConverter {

    /// 汉字转带声调拼音；withTones=false 时去掉变音符。
    /// 示例：「今天」→ "jīn tiān"
    func pinyin(for hanzi: String, withTones: Bool = true) -> String {
        let cf = NSMutableString(string: hanzi) as CFMutableString
        CFStringTransform(cf, nil, kCFStringTransformMandarinLatin, false)
        if !withTones {
            CFStringTransform(cf, nil, kCFStringTransformStripCombiningMarks, false)
        }
        return (cf as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 提取声调序列（1–4，轻声=5）。
    /// 示例：「今天」→ [1, 1]
    func toneSequence(for hanzi: String) -> [Int] {
        let syllables = pinyin(for: hanzi, withTones: true)
            .split(separator: " ")
            .map(String.init)
        return syllables.map { detectTone(syllable: $0) }
    }

    /// 从单个拼音音节中检测声调（通过变音符 Unicode 组合标记）。
    /// āēīōūǖ=1（ˉ U+0304）/ áéíóúǘ=2（´ U+0301）/ ǎěǐǒǔǚ=3（ˇ U+030C）/ àèìòùǜ=4（` U+0300）/ else=5
    private func detectTone(syllable: String) -> Int {
        for scalar in syllable.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.value {
            case 0x0304: return 1
            case 0x0301: return 2
            case 0x030C: return 3
            case 0x0300: return 4
            default: continue
            }
        }
        return 5  // 轻声
    }
}
