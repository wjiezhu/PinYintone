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
        let optionSource: String?          // B02 的国家列表来自平台本地化资源
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

    static func load(_ formKey: String, bundle: Bundle = .main) -> SurveyForm? {
        guard let url = bundle.url(forResource: formKey, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try? dec.decode(SurveyForm.self, from: data)
    }
}
