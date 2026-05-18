import Foundation

final class FeedbackTemplateLoader {
    static let shared = FeedbackTemplateLoader()
    private init() {}

    /// 按评分等级和语言返回多语种反馈模板文本
    /// language: "fr" | "zh" | "en" | "ar"
    func template(for grade: FeedbackGrade, language: String) -> String {
        fatalError("TODO: 实现")
    }
}
