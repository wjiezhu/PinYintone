import XCTest
@testable import PinYintone

/// 研究授权流程的硬约束（需求 §2）。
@MainActor
final class ResearchConsentFlowTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ResearchConsent.shared.withdraw()
        ResearchIdentity.shared.clearOnWithdrawal()
        ResearchEventLog.shared.clearPendingOnWithdrawal()
        UserDefaults.standard.removeObject(forKey: "pt_research_manifest_config_id")
    }
    override func tearDown() {
        ResearchConsent.shared.withdraw()
        ResearchIdentity.shared.clearOnWithdrawal()
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

    /// 谢绝后不得采集，且状态被记住以免反复打扰
    func testDeclineStopsCollectionAndIsRemembered() {
        ResearchConsent.shared.decline()
        XCTAssertFalse(ResearchConsent.shared.allowsResearchCollection)
        ResearchEventLog.shared.eligibility = .eligible
        ResearchEventLog.shared.window = .init(start: Date().addingTimeInterval(-60),
                                               end: Date().addingTimeInterval(3600))
        XCTAssertFalse(ResearchEventLog.shared.log(.historyOpened),
                       "谢绝研究后不得产生任何研究事件")
    }

    /// 未配置 manifest 时不得纳入——不能猜一个默认配置
    func testEnrollFailsWithoutManifest() async {
        do {
            try await ResearchEnrollment.enrollCurrentUser(consentLanguage: "zh")
            XCTFail("未配置 manifest 时不应纳入成功")
        } catch {
            XCTAssertFalse(ResearchIdentity.shared.isEnrolled)
        }
    }

    /// 撤回：即便联网失败，端侧也必须立即停采并清队列
    func testWithdrawStopsCollectionEvenIfOffline() async {
        ResearchConsent.shared.grant(textVersion: "c1", language: "zh")
        ResearchIdentity.shared.store(participantID: "p1", manifestID: "m1", studyID: "s1")
        ResearchEventLog.shared.eligibility = .eligible
        ResearchEventLog.shared.window = .init(start: Date().addingTimeInterval(-60),
                                               end: Date().addingTimeInterval(3600))
        ResearchEventLog.shared.log(.historyOpened)
        XCTAssertFalse(ResearchEventLog.shared.pending.isEmpty)

        await ResearchEnrollment.withdraw(language: "zh")   // 无后端，联网必失败

        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty, "撤回须清空待传队列")
        XCTAssertFalse(ResearchConsent.shared.allowsResearchCollection)
        XCTAssertFalse(ResearchIdentity.shared.isEnrolled)
    }
}
