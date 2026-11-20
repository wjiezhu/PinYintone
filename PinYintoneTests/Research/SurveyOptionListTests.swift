import XCTest
@testable import PinYintone

/// 国籍题与语言题的选项来自标准代码表（研究者 2026-11-18 要求）：
/// 列表完整、存的是代码、显示名跟问卷语言走、旧答案仍能对上。
@MainActor
final class SurveyOptionListTests: XCTestCase {

    private let languages = ["zh", "en", "fr", "ar", "es", "it"]

    private func background() throws -> SurveyForm {
        try XCTUnwrap(SurveyFormLoader.bundled["background_v1"])
    }

    private func question(_ id: String) throws -> SurveyForm.Question {
        try XCTUnwrap(try background().questions.first { $0.questionId == id })
    }

    // MARK: - 代码表本身

    /// ISO 3166-1 正式分配的两位代码是 249 个，一个不多一个不少
    func testRegionListIsTheFullISO3166List() throws {
        let list = try XCTUnwrap(SurveyOptionLists.list("iso3166_1_alpha2"))
        XCTAssertEqual(list.kind, .region)
        XCTAssertEqual(list.codes.count, 249)
        XCTAssertEqual(Set(list.codes).count, 249, "有重复代码")
        for code in list.codes {
            XCTAssertEqual(code.count, 2, code)
            XCTAssertEqual(code, code.uppercased(), code)
        }
        for code in ["MA", "CN", "FR", "ES", "IT", "DZ", "TN", "EG", "US", "SN"] {
            XCTAssertTrue(list.codes.contains(code), "缺 \(code)")
        }
        // 非正式分配的代码不进列表（科索沃 XK、休达与梅利利亚 EA 等是用户自定或保留代码）
        for code in ["XK", "EA", "IC", "AC", "EU", "UK"] {
            XCTAssertFalse(list.codes.contains(code), "\(code) 不是 ISO 3166-1 正式代码")
        }
    }

    /// ISO 639-1 的 183 个两位代码都在，另有预置选项用到的三个三位代码
    func testLanguageListCoversISO639_1() throws {
        let list = try XCTUnwrap(SurveyOptionLists.list("iso639"))
        XCTAssertEqual(list.kind, .language)
        XCTAssertEqual(Set(list.codes).count, list.codes.count, "有重复代码")
        XCTAssertEqual(list.codes.filter { $0.count == 2 }.count, 183)
        XCTAssertEqual(Set(list.codes.filter { $0.count != 2 }), ["ary", "arb", "ber"])
        for code in ["ar", "fr", "en", "zh", "es", "it", "de", "pt", "tr", "wo", "tl"] {
            XCTAssertTrue(list.codes.contains(code), "缺 \(code)")
        }
        for code in list.codes {
            XCTAssertEqual(code, code.lowercased(), code)
        }
    }

    func testUnknownSourceGivesNoList() {
        XCTAssertNil(SurveyOptionLists.list(nil))
        XCTAssertNil(SurveyOptionLists.list("not_a_list"))
        XCTAssertTrue(SurveyOptionLists.rows(source: "not_a_list", language: "en").isEmpty)
        XCTAssertNotNil(SurveyOptionLists.version)
    }

    // MARK: - 显示名

    /// 六种界面语言下每个国家与地区都有名称，不会把代码直接显示给人看
    func testEveryRegionHasANameInAllSixLanguages() throws {
        let list = try XCTUnwrap(SurveyOptionLists.list("iso3166_1_alpha2"))
        for language in languages {
            for code in list.codes {
                let name = SurveyOptionLists.name(for: code, kind: .region, language: language)
                XCTAssertFalse(name.isEmpty, "\(language) \(code)")
                XCTAssertNotEqual(name, code, "\(language) 下 \(code) 没有名称")
            }
        }
    }

    /// 语言名同样六种语言都有（系统缺某种译名时退回英语，不显示代码）
    func testEveryLanguageHasANameInAllSixLanguages() throws {
        let list = try XCTUnwrap(SurveyOptionLists.list("iso639"))
        for language in languages {
            for code in list.codes {
                let name = SurveyOptionLists.name(for: code, kind: .language, language: language)
                XCTAssertNotEqual(name, code, "\(language) 下 \(code) 没有名称")
            }
        }
    }

    func testNamesFollowTheSurveyLanguage() {
        XCTAssertEqual(SurveyOptionLists.name(for: "FR", kind: .region, language: "zh"), "法国")
        XCTAssertEqual(SurveyOptionLists.name(for: "FR", kind: .region, language: "it"), "Francia")
        XCTAssertEqual(SurveyOptionLists.name(for: "de", kind: .language, language: "en"), "German")
        XCTAssertEqual(SurveyOptionLists.name(for: "de", kind: .language, language: "zh"), "德语")
        // 法语、西语、意语的语言名在系统里是小写开头，列表里首字母大写
        XCTAssertEqual(SurveyOptionLists.name(for: "de", kind: .language, language: "fr"), "Allemand")
        XCTAssertEqual(SurveyOptionLists.name(for: "de", kind: .language, language: "es"), "Alemán")
    }

    /// 系统不认识的代码原样返回，不编造名称
    func testUnknownCodeFallsBackToTheCode() {
        XCTAssertEqual(SurveyOptionLists.name(for: "zzz_unknown", kind: .language, language: "fr"),
                       "zzz_unknown")
    }

    // MARK: - 列表与搜索

    func testRowsAreCompleteSortedAndSearchable() throws {
        for language in languages {
            let rows = SurveyOptionLists.rows(source: "iso3166_1_alpha2", language: language)
            XCTAssertEqual(rows.count, 249, language)
            XCTAssertEqual(Set(rows.map(\.code)).count, 249, language)
        }
        let en = SurveyOptionLists.rows(source: "iso3166_1_alpha2", language: "en").map(\.name)
        XCTAssertEqual(en, en.sorted { $0.compare($1, options: .caseInsensitive, range: nil,
                                                  locale: Locale(identifier: "en")) == .orderedAscending })

        // 按名称搜（不分大小写、不分重音），也可以直接输代码
        XCTAssertEqual(SurveyOptionLists.rows(source: "iso3166_1_alpha2", language: "en",
                                              query: "moroc").map(\.code), ["MA"])
        XCTAssertTrue(SurveyOptionLists.rows(source: "iso3166_1_alpha2", language: "fr",
                                             query: "senegal").map(\.code).contains("SN"),
                      "Sénégal 应能用不带重音的写法搜到")
        XCTAssertEqual(SurveyOptionLists.rows(source: "iso3166_1_alpha2", language: "zh",
                                              query: "摩洛哥").map(\.code), ["MA"])
        XCTAssertTrue(SurveyOptionLists.rows(source: "iso3166_1_alpha2", language: "ar",
                                             query: "ma").map(\.code).contains("MA"))
        XCTAssertTrue(SurveyOptionLists.rows(source: "iso639", language: "en",
                                             query: "portug").map(\.code).contains("pt"))
        XCTAssertTrue(SurveyOptionLists.rows(source: "iso3166_1_alpha2", language: "en",
                                             query: "no such place").isEmpty)
    }

    /// 预置选项自带的译名在完整列表里同样生效，同一种语言不出现两种叫法
    func testPresetLabelsOverrideSystemNames() {
        let rows = SurveyOptionLists.rows(source: "iso639", language: "zh",
                                          overrides: ["ary": "达里贾语（摩洛哥阿拉伯方言）"])
        XCTAssertEqual(rows.first { $0.code == "ary" }?.name, "达里贾语（摩洛哥阿拉伯方言）")
        XCTAssertEqual(SurveyOptionLists.rows(source: "iso639", language: "zh", query: "达里贾",
                                              overrides: ["ary": "达里贾语（摩洛哥阿拉伯方言）"]).map(\.code),
                       ["ary"])
    }

    // MARK: - 问卷定义

    /// 国籍题：完整列表 + MA 预置；不再有自由填写的「其他国籍」
    func testNationalityQuestionUsesTheFullCountryList() throws {
        let b02 = try question("B02")
        XCTAssertEqual(b02.optionSource, "iso3166_1_alpha2")
        XCTAssertEqual(b02.options.map(\.code), ["MA", "prefer_not"])
        XCTAssertEqual(try background().exclusiveCodes(in: b02), ["prefer_not"])
        let list = try XCTUnwrap(SurveyOptionLists.list(b02.optionSource))
        XCTAssertTrue(list.codes.contains("MA"), "纳入规则 eligibility-2.0 用的代码必须在列表里")
    }

    /// 语言题：预置选项的代码都是列表里的 ISO 639 代码，六种语言的译名齐全
    func testLanguageQuestionsStoreISO639Codes() throws {
        let list = try XCTUnwrap(SurveyOptionLists.list("iso639"))
        for id in ["B04", "B05"] {
            let q = try question(id)
            XCTAssertEqual(q.optionSource, "iso639", id)
            for opt in q.options where opt.textInput == nil && opt.exclusive != true {
                XCTAssertTrue(list.codes.contains(opt.code), "\(id).\(opt.code) 不是列表里的代码")
                for language in languages {
                    XCTAssertFalse((opt.label[language] ?? "").isEmpty, "\(id).\(opt.code) 缺 \(language)")
                }
            }
            XCTAssertTrue(q.options.contains { $0.code == "other" && $0.textInput != nil },
                          "\(id) 列表里没有的语言仍可填写")
            XCTAssertEqual(q.options.last?.code, "prefer_not")
        }
        XCTAssertEqual(try question("B04").options.map(\.code),
                       ["ary", "ber", "arb", "fr", "es", "it", "other", "prefer_not"])
    }

    /// 题面与按钮提到的「搜索…」在六种语言里都有
    func testSearchStringsExistInAllSixLanguages() {
        for key in ["search_country", "search_language"] {
            for language in languages {
                XCTAssertNotEqual(SurveyUIStrings.text(key, language), key, "\(key) 缺 \(language)")
            }
        }
        XCTAssertNotEqual(SurveyUIStrings.text("search_language", "ar"),
                          SurveyUIStrings.text("search_language", "en"))
    }

    // MARK: - 旧答案

    /// 1.2 及更早版本的语言代码都能对到 ISO 639 代码，且对到的代码都在列表里
    func testLegacyLanguageCodesMapOntoTheList() throws {
        let list = try XCTUnwrap(SurveyOptionLists.list("iso639"))
        let legacy = ["darija", "amazigh", "msa", "french", "english", "chinese", "spanish", "italian"]
        XCTAssertEqual(Set(SurveyOptionLists.legacyLanguageCodes.keys), Set(legacy))
        for code in legacy {
            XCTAssertTrue(list.codes.contains(SurveyOptionLists.canonicalLanguageCode(code)), code)
        }
        XCTAssertEqual(SurveyOptionLists.canonicalLanguageCode("darija"), "ary")
        XCTAssertEqual(SurveyOptionLists.canonicalLanguageCode("fr"), "fr", "已是 ISO 代码的不动")
        XCTAssertEqual(SurveyOptionLists.canonicalLanguageCode("other"), "other")
        XCTAssertEqual(SurveyOptionLists.canonicalLanguageCode("prefer_not"), "prefer_not")
    }

    // MARK: - 作答

    /// 从完整列表里选的国籍、语言与预置选项一起提交，提交的是代码
    func testListedCodesAreSubmittedAsCodes() throws {
        var draft = SurveyDraft()
        draft.selections = ["B02": ["MA", "FR"], "B04": ["ary", "wo"], "B05": ["de", "other"]]
        draft.texts["B05.other"] = "Hassaniya"
        let list = SurveyFormView.answers(for: try background(), draft: draft)
        let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.questionID, $0) })
        XCTAssertEqual(byID["B02"]?.optionCodes, ["FR", "MA"])
        XCTAssertEqual(byID["B04"]?.optionCodes, ["ary", "wo"])
        XCTAssertEqual(byID["B05"]?.optionCodes, ["de", "other"])
        XCTAssertEqual(byID["B05"]?.textValue, "Hassaniya")
    }

    /// 与「不愿回答」互斥：选了列表里的一项，互斥项就取消；再点一次是取消
    func testListedCodeClearsExclusiveOption() {
        let afterPick = SurveyFormView.toggling("FR", in: ["prefer_not"], exclusives: ["prefer_not"])
        XCTAssertEqual(afterPick, ["FR"])
        XCTAssertEqual(SurveyFormView.toggling("ES", in: afterPick, exclusives: ["prefer_not"]), ["FR", "ES"])
        XCTAssertEqual(SurveyFormView.toggling("FR", in: afterPick, exclusives: ["prefer_not"]), [])
    }

    /// 国籍仍按代码参与纳入判定所需的派生字段
    func testNationalitiesFromTheFullListReachEligibility() throws {
        var draft = SurveyDraft()
        draft.selections = ["B01": ["adult"], "B02": ["DZ", "FR"], "B03": ["hsk2"]]
        let outcome = SurveyOutcome(formKey: "background_v1", formVersion: "v", translationVersion: "t",
                                    language: "fr",
                                    answers: SurveyFormView.answers(for: try background(), draft: draft),
                                    status: "partial", startedAt: nil, submittedAt: nil)
        XCTAssertEqual(outcome.nationalities, ["DZ", "FR"])
    }

    // MARK: - 注册页「会说的语言」

    /// 注册页的预置项都是 ISO 639 代码（「其他」除外），与问卷语言题同一张表
    func testSignupPresetsAreISO639Codes() throws {
        let list = try XCTUnwrap(SurveyOptionLists.list(SpokenLanguage.listSource))
        XCTAssertEqual(list.kind, .language)
        let codes = SpokenLanguage.presets.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "预置项不重复")
        XCTAssertEqual(codes.last, "other", "「其他」排最后")
        for code in codes.dropLast() {
            XCTAssertTrue(list.codes.contains(code), code)
        }
        XCTAssertEqual(Array(codes.prefix(2)), ["ary", "fr"], "摩洛哥被试的常见语言优先")
    }

    /// 2.1 及更早注册页的自定代码都对到预置项；旧代码与 ISO 代码不撞，混在一起也分得清
    func testLegacySignupCodesMapOntoPresets() throws {
        let list = try XCTUnwrap(SurveyOptionLists.list(SpokenLanguage.listSource))
        let presets = Set(SpokenLanguage.presets.map(\.code))
        let legacy = ["darija", "arabic", "amazigh", "french", "english", "spanish", "italian"]
        XCTAssertEqual(Set(SpokenLanguage.legacyCodes.keys), Set(legacy))
        for code in legacy {
            XCTAssertFalse(list.codes.contains(code), "旧代码与 ISO 代码撞了：\(code)")
            XCTAssertTrue(presets.contains(SpokenLanguage.canonicalCode(code)), code)
        }
        XCTAssertEqual(SpokenLanguage.canonicalCode("arabic"), "arb")
        XCTAssertEqual(SpokenLanguage.canonicalCode("other"), "other", "「其他」两版相同")
        XCTAssertEqual(SpokenLanguage.canonicalCode("fr"), "fr", "已是 ISO 代码的不动")
    }

    /// 预置项用本地化名（完整列表里也一样），其余代码由系统给名
    func testSignupLanguageNames() {
        XCTAssertEqual(SpokenLanguage.name(for: "ary", language: "en"),
                       NSLocalizedString("lang_darija", comment: ""))
        XCTAssertEqual(SpokenLanguage.presetNames["ber"], NSLocalizedString("lang_amazigh", comment: ""))
        XCTAssertEqual(SpokenLanguage.name(for: "de", language: "en"), "German")
        XCTAssertEqual(SpokenLanguage.name(for: "de", language: "fr"), "Allemand")
        let rows = SurveyOptionLists.rows(source: SpokenLanguage.listSource, language: "en",
                                          overrides: SpokenLanguage.presetNames)
        XCTAssertEqual(rows.first { $0.code == "ary" }?.name, NSLocalizedString("lang_darija", comment: ""))
    }
}
