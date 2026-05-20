import NaturalLanguage

/// iOS 原生 NLTokenizer 离线分词，无第三方依赖。
struct ChineseTokenizer {

    /// 输入中文字符串，返回分词数组（过滤标点和空白）。
    /// 示例：「今天天气很好」→ ["今天", "天气", "很", "好"]
    func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.simplifiedChinese)
        tokenizer.string = text

        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            // 过滤空白与纯标点
            if !token.isEmpty,
               !token.allSatisfy({ $0.isWhitespace || $0.isPunctuation }) {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }
}
