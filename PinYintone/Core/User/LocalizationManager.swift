import Combine
import Foundation
import SwiftUI

/// 运行时语言切换：通过重定向 Bundle.main 的本地化查找，使所有 NSLocalizedString
/// 立即使用用户选择的语言，无需重启 App。
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// 受支持的语言（code → 显示名）；code 对应 OnboardingFlowView 的选择
    static let supported: [(code: String, flag: String, label: String)] = [
        ("fr", "🇫🇷", "Français"),
        ("zh", "🇨🇳", "中文"),
        ("en", "🇬🇧", "English"),
        ("ar", "🇸🇦", "العربية"),
    ]

    static let storageKey = "pt_app_language"

    @Published private(set) var language: String
    /// 语言变更时刷新整棵视图树（强制 NSLocalizedString 重新求值）
    @Published private(set) var refreshToken = UUID()

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        language = stored ?? Self.systemDefault
        Self.applyBundle(language)
    }

    /// 系统首选语言落到受支持列表，否则回退法语
    static var systemDefault: String {
        let pref = Locale.preferredLanguages.first ?? "fr"
        let code = String(pref.prefix(2))
        return supported.map(\.code).contains(code) ? code : "fr"
    }

    var locale: Locale { Locale(identifier: language) }
    var layoutDirection: LayoutDirection { language == "ar" ? .rightToLeft : .leftToRight }

    func setLanguage(_ code: String) {
        guard code != language,
              Self.supported.map(\.code).contains(code) else { return }
        UserDefaults.standard.set(code, forKey: Self.storageKey)
        language = code
        Self.applyBundle(code)
        refreshToken = UUID()
    }

    /// 将 Bundle.main 的类替换为 LocalizedBundle，并指向所选语言的 .lproj
    static func applyBundle(_ code: String) {
        // 选择列表用 "zh"，但资源目录是 "zh-Hans"
        let resource = (code == "zh") ? "zh-Hans" : code
        object_setClass(Bundle.main, LocalizedBundle.self)
        let path = Bundle.main.path(forResource: resource, ofType: "lproj")
        LocalizedBundle.override = path.flatMap { Bundle(path: $0) }
    }
}

/// Bundle.main 的替身：本地化查找改走 override 指向的 .lproj
final class LocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var override: Bundle?

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        LocalizedBundle.override?.localizedString(forKey: key, value: value, table: tableName)
            ?? super.localizedString(forKey: key, value: value, table: tableName)
    }
}
