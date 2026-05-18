import NaturalLanguage

/// iOS 原生 NLTokenizer 离线分词，无第三方依赖
struct ChineseTokenizer {

    /// 输入中文字符串，返回分词数组（过滤标点和空白）
    /// 示例：「今天天气很好」→ ["今天", "天气", "很", "好"]
    func tokenize(_ text: String) -> [String] {
        fatalError("TODO: 实现")
    }
}
