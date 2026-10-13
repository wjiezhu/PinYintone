import XCTest
@testable import PinYintone

/// 研究授权流程的硬约束（需求 §2）。
@MainActor
final class ResearchConsentFlowTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ResearchTestSupport.freshAccount()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    /// 四段说明 + 联系方式 + 勾选项在四种语言下都必须有真实译文
    func testConsentCopyExistsInAllFourLanguages() throws {
        let keys = ["consent_title", "consent_purpose_title", "consent_purpose_body",
                    "consent_data_title", "consent_data_body",
                    "consent_use_title", "consent_use_body",
                    "consent_withdraw_title", "consent_withdraw_body",
                    "consent_contact", "consent_checkbox",
                    "consent_agree", "consent_decline", "consent_decline_hint"]
        for lang in ["zh-Hans", "en", "fr", "ar"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"),
                                     "\(lang) 未随包发布")
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(value, key, "\(lang) 缺少 \(key) 的译文")
                XCTAssertFalse(value.isEmpty, "\(lang) 的 \(key) 为空")
            }
        }
    }

    /// 按语言取串。NSLocalizedString 取的是**运行环境语言**，
    /// 断言具体措辞必须显式指定 lproj，否则测试只是在验证跑测的那一种语言。
    private func string(_ key: String, lang: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// 采集内容说明必须写明录音本身不上传（需求 §7）
    func testDataSectionStatesRecordingsAreNotUploaded() throws {
        let zh = try string("consent_data_body", lang: "zh-Hans")
        XCTAssertTrue(zh.contains("录音"), "必须写明录音如何处理")
        XCTAssertTrue(zh.contains("不会上传"), "必须写明录音本身不上传")

        let en = try string("consent_data_body", lang: "en")
        XCTAssertTrue(en.lowercased().contains("recording"))
        XCTAssertTrue(en.lowercased().contains("not uploaded"))
    }

    /// 联系方式必须出现在四种语言的说明里（字典 §16）
    func testContactChannelPresentInAllLanguages() throws {
        for lang in ["zh-Hans", "en", "fr", "ar"] {
            XCTAssertTrue(try string("consent_contact", lang: lang)
                .contains("joyouo409@gmail.com"), "\(lang) 缺少联系方式")
        }
    }

    /// 同意只是「已同意待纳入」——**不等于已参加**，不产生任何研究日志
    func testGrantIsNotEnrollment() {
        ResearchConsent.grant()
        let s = ResearchStore.shared.state
        XCTAssertEqual(s.participation, .consentedPending)
        XCTAssertEqual(s.consentVersion, ResearchConsent.textVersion)
        XCTAssertNotNil(s.consentAt)
        XCTAssertFalse(ResearchGate.shouldCollect())
        XCTAssertFalse(ResearchEventLog.shared.log(.historyOpened))
    }

    /// 同意时记的是用户在 App 内选择并实际看到的界面语言，不是系统区域（R08）
    func testConsentLanguageIsTheAppLanguageNotTheSystemLocale() {
        let before = LocalizationManager.shared.language
        defer { LocalizationManager.shared.setLanguage(before) }
        for language in ["ar", "fr", "zh", "en"] {
            LocalizationManager.shared.setLanguage(language)
            ResearchConsent.grant()
            XCTAssertEqual(ResearchStore.shared.state.consentLanguage, language)
            XCTAssertTrue(["zh", "en", "fr", "ar"].contains(
                ResearchStore.shared.state.consentLanguage ?? ""))
        }
    }

    /// 谢绝后不采集，且状态被记住；之后仍可由用户主动重新进入
    func testDeclineStopsCollectionAndIsRememberedButCanBeReopenedByTheUser() {
        ResearchConsent.decline()
        let s = ResearchStore.shared.state
        XCTAssertEqual(s.participation, .declined)
        XCTAssertFalse(ResearchGate.shouldCollect())
        XCTAssertTrue(ResearchConsent.canOfferInvitation(s), "主动重新进入时可以再问")
    }

    /// 已参与、已退出、已判不符合者不再被邀请
    func testNoInvitationOnceEnrolledWithdrawnOrExcluded() {
        for participation in [ResearchState.Participation.enrolled, .withdrawn, .ineligible] {
            var s = ResearchState()
            s.participation = participation
            XCTAssertFalse(ResearchConsent.canOfferInvitation(s), "\(participation)")
        }
    }

    /// 关键题当时没答（无法判定）的人可以主动回来重填；明确不符合的不行
    func testRestartOnlyForUndeterminedEligibility() {
        ResearchStore.shared.update { s in
            s.participation = .ineligible
            s.eligibility = "excluded:age"
        }
        ResearchConsent.restart()
        XCTAssertEqual(ResearchStore.shared.state.participation, .ineligible)

        ResearchStore.shared.update { $0.eligibility = "pending" }
        ResearchConsent.restart()
        XCTAssertEqual(ResearchStore.shared.state.participation, .notAsked)
    }

    /// 未审定的同意文本不能冒充正式版本
    func testShippedConsentTextIsStillMarkedUnpublished() {
        XCTAssertTrue(ResearchConsent.textVersion.contains("unpublished"),
                      "研究者审定文本后才可去掉该标记，并须同步四语文案与配置")
    }
}
