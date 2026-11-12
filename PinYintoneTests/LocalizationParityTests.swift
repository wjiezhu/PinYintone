import XCTest
@testable import PinYintone

/// 四种语言的界面文案必须齐全、对应（需求 U07）。
///
/// 缺一条译文不会让 App 崩溃——它会把键名原样显示给学习者（比如
/// 「tone_stage_ready」），而只看中文界面的开发者永远发现不了。
final class LocalizationParityTests: XCTestCase {

    private let languages = ["zh-Hans", "en", "fr", "ar", "es", "it"]

    private func table(_ language: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                  inDirectory: nil, forLocalization: language),
                                 "\(language) 的文案未随包发布")
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    func testAllFourLanguagesHaveExactlyTheSameKeys() throws {
        let reference = Set(try table("zh-Hans").keys)
        XCTAssertGreaterThan(reference.count, 250)
        for language in languages.dropFirst() {
            let keys = Set(try table(language).keys)
            XCTAssertEqual(reference.subtracting(keys), [], "\(language) 缺少这些文案")
            XCTAssertEqual(keys.subtracting(reference), [], "\(language) 多出这些文案")
        }
    }

    func testNoEmptyTranslations() throws {
        for language in languages {
            for (key, value) in try table(language) {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(language) 的 \(key) 是空的")
            }
        }
    }

    /// 占位符必须一致：中文里是 %1$d / %2$d，译文里就不能少一个或换成 %@，
    /// 否则轻则显示错乱，重则运行时崩溃。
    func testFormatSpecifiersMatchAcrossLanguages() throws {
        func specifiers(_ s: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: "%(\\d+\\$)?[@dfs]")
            return regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
                .map { String(s[Range($0.range, in: s)!]) }.sorted()
        }
        let reference = try table("zh-Hans")
        for language in languages.dropFirst() {
            let other = try table(language)
            for (key, value) in reference {
                XCTAssertEqual(specifiers(value), specifiers(other[key] ?? ""),
                               "\(language) 的 \(key) 占位符与中文不一致")
            }
        }
    }

    /// 本轮新增与改动的界面文案在四种语言里都有真实译文（不是照抄键名或中文）
    func testNewScreensAreTranslated() throws {
        let keys = ["tab_practice", "tab_history", "tab_settings", "home_continue", "home_words",
                    "tone_stage_ready", "tone_stage_recording", "tone_fail_mic_denied",
                    "result_title", "result_try_again", "chart_empty", "word_picker_title",
                    "self_test_title", "self_test_done_body", "history_kind_self_test",
                    "history_status_technical", "research_section", "research_withdraw",
                    "research_status_pending", "research_ineligible_body",
                    "survey_status_saved_pending", "survey_post_invite_body",
                    "consent_draft_notice"]
        let zh = try table("zh-Hans")
        for language in ["en", "fr", "ar"] {
            let other = try table(language)
            for key in keys {
                let value = try XCTUnwrap(other[key], "\(language) 缺 \(key)")
                XCTAssertNotEqual(value, key)
                XCTAssertNotEqual(value, zh[key], "\(language) 的 \(key) 还是中文")
            }
        }
    }

    /// 界面上不再出现「前测 / 后测」的说法——那套强制流程已经取消（需求 R06）
    func testNoPretestPosttestWordingRemains() throws {
        let banned = ["zh-Hans": ["前测", "后测"], "en": ["pre-test", "post-test", "pretest", "posttest"],
                      "fr": ["pré-test", "post-test"], "ar": ["الاختبار القبلي", "البعدي"]]
        for (language, words) in banned {
            for (key, value) in try table(language) {
                for word in words {
                    XCTAssertFalse(value.lowercased().contains(word.lowercased()),
                                   "\(language) 的 \(key) 仍含「\(word)」")
                }
            }
        }
    }

    /// 参考曲线来自设备端合成，不能宣称是母语者真人标准音（需求 R03）
    func testReferenceCurveIsNotLabelledAsANativeSpeaker() throws {
        let banned = ["zh-Hans": "母语者", "en": "native", "fr": "natif", "ar": "متحدث أصلي"]
        for (language, word) in banned {
            let value = try XCTUnwrap(try table(language)["legend_native"])
            XCTAssertFalse(value.lowercased().contains(word.lowercased()),
                           "\(language) 的图例仍把参考曲线称作「\(word)」")
        }
    }
}
