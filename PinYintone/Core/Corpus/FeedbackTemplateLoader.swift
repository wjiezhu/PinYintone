import Foundation

/// 三级（四档）双语反馈模板加载器（对应论文 3.4 节情感反馈模块）。
/// 从 Bundle 内 feedback_templates.json 按「评分等级 → 语言」随机抽取一条反馈语句。
/// 语言沿用 app 四语：fr / zh / en / ar。
final class FeedbackTemplateLoader {
    static let shared = FeedbackTemplateLoader()

    /// [gradeRawValue: [language: [模板语句]]]
    private let templates: [String: [String: [String]]]

    private init() {
        templates = Self.load()
    }

    /// 按评分等级和语言返回一条反馈模板文本。
    /// - Parameters:
    ///   - grade: DTW 评分等级
    ///   - language: "fr" | "zh" | "en" | "ar"
    func template(for grade: FeedbackGrade, language: String) -> String {
        let byLanguage = templates[grade.rawValue]
        // 语言缺失时回退英文，再回退任意可用语言
        let pool = byLanguage?[language]
            ?? byLanguage?["en"]
            ?? byLanguage?.values.first
            ?? []
        return pool.randomElement() ?? Self.fallback(grade, language)
    }

    // MARK: - 私有

    private static func load() -> [String: [String: [String]]] {
        guard let url = Bundle.main.url(forResource: "feedback_templates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: [String]]].self, from: data)
        else { return [:] }
        return decoded
    }

    /// JSON 缺失时的兜底文案
    private static func fallback(_ grade: FeedbackGrade, _ language: String) -> String {
        switch grade {
        case .excellent:     return "👍"
        case .good:          return "🙂"
        case .needsPractice: return "💪"
        case .fail:          return "🔁"
        }
    }
}
