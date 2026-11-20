import Foundation

/// 问卷表单定义（字典 §10 末）。
///
/// 字典要求「表单定义随版本保存为**只读配置**，包括全部题面、选项标签、
/// 选项码、互斥规则、最大选择数、译文及核校日期，**不能只存一个可被覆盖的
/// 前端链接**」。因此题目定义是随包发布的 JSON 资源，不是硬编码的 UI。
///
/// 任何改动都必须生成新版本文件，**不覆盖已收集数据所依据的题目定义**。
nonisolated struct SurveyForm: Codable {
    struct Option: Codable {
        let code: String
        let label: [String: String]        // 语言码 → 显示文字
        /// 与其余选项互斥（如「没有困难」「不愿回答」）
        let exclusive: Bool?
        /// 李克特题的 1–5；`cannot_judge` 无此值，**不计分且不得存为 0**
        let value: Int?
        let textInput: TextInput?
    }
    struct TextInput: Codable {
        let maxChars: Int
        let hint: [String: String]?
        let optional: Bool?
    }
    struct Question: Codable {
        let questionId: String
        let type: String                   // single | multi | text
        let question: [String: String]
        let hint: [String: String]?
        let options: [Option]
        let maxSelections: Int?            // PRE06 为 2
        let textInput: TextInput?
        let note: String?
        /// 选项另由一份标准代码表补全（`SurveyOptionLists`）：
        /// `iso3166_1_alpha2`（国籍题）或 `iso639`（语言题）。预置选项仍排在前面
        let optionSource: String?
    }

    let formKey: String
    let formVersion: String
    let translationVersion: String
    let title: [String: String]
    let intro: [String: String]?
    let scoringNote: String?
    let questions: [Question]

    /// 供选项互斥/上限校验用：该题的互斥选项码
    func exclusiveCodes(in question: Question) -> Set<String> {
        Set(question.options.filter { $0.exclusive == true }.map(\.code))
    }
}

nonisolated enum SurveyFormLoader {
    static let formKeys = ["background_v1", "tone_needs_v1", "usability_short_v1"]

    /// 随包发布的全部问卷定义，按 formKey 索引。配置自检与邀请快照都读它——
    /// 版本号只有一个来源，就是 App 实际携带的那份 JSON。
    static let bundled: [String: SurveyForm] = {
        var out: [String: SurveyForm] = [:]
        for key in formKeys { out[key] = load(key) }
        return out
    }()

    static func load(_ formKey: String, bundle: Bundle = .main) -> SurveyForm? {
        guard let url = bundle.url(forResource: formKey, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try? dec.decode(SurveyForm.self, from: data)
    }
}

/// 问卷界面上的固定文案（上一题、跳过、稍后填写…）。
///
/// 与题面同出一份四语稿（`survey_ui_v1.json`），并**跟着问卷的语言走**而不是
/// 跟着 App 当前语言走：问卷在邀请时就定下了语言，之后即便用户改了界面语言，
/// 这份问卷从题面到按钮仍是同一种语言。
nonisolated enum SurveyUIStrings {
    private struct File: Decodable {
        let strings: [String: [String: String]]
    }

    private static let strings: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "survey_ui_v1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return file.strings
    }()

    static func text(_ key: String, _ language: String) -> String {
        strings[key]?[language] ?? strings[key]?["en"] ?? key
    }
}

/// 由标准代码表提供的问卷选项（国籍题、语言题）。
///
/// - **保存的只有代码**：国家与地区是 ISO 3166-1 两位代码，语言是 ISO 639 代码。
/// - 代码表随包发布（`survey_option_lists_v1.json`），不取系统「当前有哪些」——
///   不同系统版本的列表不一样，问卷的选项不能跟着系统变。
/// - 显示名由系统按**问卷语言**本地化；系统没有这种语言的名称时退回英语，再退回代码。
///   题目里预置选项自带的译名优先（如「达里贾语」），由调用方传入。
nonisolated enum SurveyOptionLists {
    enum Kind: String, Decodable { case region, language }

    struct List: Decodable {
        let standard: String
        let kind: Kind
        let codes: [String]
    }

    struct Row: Equatable {
        let code: String
        let name: String
    }

    private struct File: Decodable {
        let listVersion: String
        let lists: [String: List]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "survey_option_lists_v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try? dec.decode(File.self, from: data)
    }()

    static var version: String? { file?.listVersion }

    /// 题目的 `option_source` 指向的代码表；没有或不认识时为 nil（该题就只有预置选项）
    static func list(_ source: String?) -> List? {
        guard let source else { return nil }
        return file?.lists[source]
    }

    private static func locale(_ language: String) -> Locale {
        Locale(identifier: language == "zh" ? "zh-Hans" : language)
    }

    /// 代码的显示名。系统不认识的代码原样返回，不编造名称。
    static func name(for code: String, kind: Kind, language: String) -> String {
        func lookup(_ locale: Locale) -> String? {
            let name: String?
            switch kind {
            case .region: name = locale.localizedString(forRegionCode: code)
            case .language: name = locale.localizedString(forLanguageCode: code)
            }
            guard let name, !name.isEmpty, name != code else { return nil }
            // 法语、西语、意语的语言名是小写开头的；列表里每行都是独立的一项，首字母大写
            return name.prefix(1).uppercased(with: locale) + name.dropFirst()
        }
        return lookup(locale(language)) ?? lookup(Locale(identifier: "en")) ?? code
    }

    /// 整份列表，按问卷语言的排序规则排好；`query` 非空时按名称或代码筛选。
    /// `overrides` 是题目预置选项自带的译名（代码 → 显示名）。
    static func rows(source: String?, language: String, query: String = "",
                     overrides: [String: String] = [:]) -> [Row] {
        guard let list = list(source) else { return [] }
        let loc = locale(language)
        let all = list.codes
            .map { Row(code: $0, name: overrides[$0] ?? name(for: $0, kind: list.kind, language: language)) }
            .sorted { $0.name.compare($1.name, options: [.caseInsensitive], range: nil, locale: loc) == .orderedAscending }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return all.filter {
            $0.name.range(of: q, options: options, locale: loc) != nil
                || $0.code.caseInsensitiveCompare(q) == .orderedSame
        }
    }

    /// `background_v1-1.2` 及更早的语言题存的是自定代码；1.3 起存 ISO 639 代码。
    /// 旧答案**不改写**，分析时按这张表对到同一种语言。
    /// `amazigh` 对 `ber`（语族）：旧选项没有区分塔马塞特、希尔哈、里夫等具体语言。
    static let legacyLanguageCodes: [String: String] = [
        "darija": "ary", "msa": "arb", "amazigh": "ber",
        "french": "fr", "english": "en", "chinese": "zh",
        "spanish": "es", "italian": "it",
    ]

    static func canonicalLanguageCode(_ code: String) -> String {
        legacyLanguageCodes[code] ?? code
    }
}
