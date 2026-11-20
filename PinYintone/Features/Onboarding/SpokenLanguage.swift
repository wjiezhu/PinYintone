import Foundation

/// 学习者会说的语言（母语 / 背景语言），注册页多选。
///
/// 研究意义：母语迁移是本研究的核心变量——达里贾（摩洛哥阿拉伯语）与法语均为
/// 非声调语言，法语有短语级语调迁移，阿拉伯语缺清双唇塞音 /p/。记录每位被试
/// 的语言背景，便于按母语组合分析声调与送气偏误。
///
/// - 存的是 **ISO 639 代码**，与背景问卷语言题用同一张表（`survey_option_lists_v1.json`
///   的 `iso639`）：常见的几种直接列出，其余从完整列表里搜；`other` 是「其他」。
/// - 2.1（构建 23）及更早的注册页存的是自定代码（`darija` / `arabic` / `french` …）。旧值**不改写**，
///   分析时按 `legacyCodes` 对到同一种语言。两套代码互不重叠，混在一起也分得清。
nonisolated enum SpokenLanguage {
    struct Preset: Identifiable, Equatable {
        let code: String
        /// 本地化显示名的 key（见 Localizable.strings）
        let localizationKey: String
        var id: String { code }
    }

    /// 完整列表用的代码表，与背景问卷语言题相同
    static let listSource = "iso639"

    /// 直接列出的几项：摩洛哥被试的常见语言优先
    static let presets: [Preset] = [
        Preset(code: "ary", localizationKey: "lang_darija"),
        Preset(code: "fr", localizationKey: "lang_french"),
        Preset(code: "arb", localizationKey: "lang_arabic"),
        Preset(code: "ber", localizationKey: "lang_amazigh"),
        Preset(code: "en", localizationKey: "lang_english"),
        Preset(code: "es", localizationKey: "lang_spanish"),
        Preset(code: "it", localizationKey: "lang_italian"),
        Preset(code: "other", localizationKey: "lang_other"),
    ]

    /// 2.1（构建 23）及更早注册页的自定代码 → ISO 639 代码。
    /// `amazigh` 对 `ber`（语族）：旧选项没有区分塔马塞特、希尔哈、里夫等具体语言。
    static let legacyCodes: [String: String] = [
        "darija": "ary", "arabic": "arb", "amazigh": "ber",
        "french": "fr", "english": "en", "spanish": "es", "italian": "it",
    ]

    static func canonicalCode(_ code: String) -> String {
        legacyCodes[code] ?? code
    }

    /// 预置项的本地化名（代码 → 显示名）。完整列表里同一个代码也用它，
    /// 同一种语言不出现两种叫法（如「达里贾」而不是系统的「摩洛哥阿拉伯语」）
    static var presetNames: [String: String] {
        Dictionary(uniqueKeysWithValues: presets.map {
            ($0.code, NSLocalizedString($0.localizationKey, comment: ""))
        })
    }

    /// 代码的显示名：预置项用本地化文案，其余由系统按界面语言给出
    static func name(for code: String, language: String) -> String {
        presetNames[code] ?? SurveyOptionLists.name(for: code, kind: .language, language: language)
    }
}
