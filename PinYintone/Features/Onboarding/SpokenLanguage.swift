import Foundation

/// 学习者会说的语言（母语 / 背景语言）。多选。
///
/// 研究意义：母语迁移是本研究的核心变量——达里贾（摩洛哥阿拉伯语）与法语均为
/// 非声调语言，法语有短语级语调迁移，阿拉伯语缺清双唇塞音 /p/。记录每位被试
/// 的语言背景，便于按母语组合分析声调与送气偏误。
///
/// `code` 随注册上报，稳定不变（勿改已有值，否则破坏历史数据对齐）。
enum SpokenLanguage: String, CaseIterable, Identifiable, Codable {
    case darija      // 摩洛哥阿拉伯语（达里贾）
    case arabic      // 标准阿拉伯语
    case french
    case english
    case spanish
    case amazigh     // 塔马齐格特（柏柏尔语）
    case other

    var id: String { rawValue }

    /// 本地化显示名的 key（见 Localizable.strings）
    var localizationKey: String { "lang_\(rawValue)" }

    var flag: String {
        switch self {
        case .darija:  return "🇲🇦"
        case .arabic:  return "🇸🇦"
        case .french:  return "🇫🇷"
        case .english: return "🇬🇧"
        case .spanish: return "🇪🇸"
        case .amazigh: return "ⵣ"
        case .other:   return "🌐"
        }
    }

    /// 展示顺序：摩洛哥被试的常见语言优先
    static var displayOrder: [SpokenLanguage] {
        [.darija, .french, .arabic, .amazigh, .english, .spanish, .other]
    }
}
