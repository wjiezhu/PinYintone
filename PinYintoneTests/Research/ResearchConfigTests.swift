import XCTest
@testable import PinYintone

/// 研究配置的可用性与兼容性自检（需求 R03、验收 A01 / A23）。
@MainActor
final class ResearchConfigTests: XCTestCase {

    private var config: ResearchConfig { .shared }

    override func setUp() {
        super.setUp()
        config.setAvailableForTesting(nil)
        ResearchTestSupport.freshAccount()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    private func served(consent: String = ResearchConsent.Text.fieldSession.rawValue,
                        eligibility: String? = ResearchEligibility.version,
                        lexicon: String? = ResearchLexicon.lexiconVersion,
                        appVersion: String? = AppEnvironment.appVersion,
                        forms: [String: [String: String]]? = nil,
                        isTest: Bool? = true,
                        start: Date = Date().addingTimeInterval(-3600),
                        end: Date = Date().addingTimeInterval(86_400)) -> APIClient.ActiveManifest {
        .init(manifestID: "m", studyID: "s", collectionStartAt: start, collectionEndAt: end,
              postTriggerCount: 5, consentVersion: consent, surveyVersion: "sv",
              rewardRuleVersion: nil, appVersion: appVersion, buildNumber: "1",
              lexiconVersion: lexicon, eligibilityVersion: eligibility,
              surveyForms: forms, isTest: isTest)
    }

    private func bundledFormSpec() -> [String: [String: String]] {
        Dictionary(uniqueKeysWithValues: SurveyFormLoader.bundled.map { key, form in
            (key, ["form_version": form.formVersion,
                   "translation_version": form.translationVersion])
        })
    }

    /// 没有配置：不开放参加，不猜一个（验收 A01）
    func testNoManifestMeansResearchIsClosed() {
        XCTAssertNil(config.manifestID)
        XCTAssertFalse(config.isOpen())
        XCTAssertFalse(ResearchEnrollment.canJoinNow())
    }

    func testMatchingManifestIsCompatible() {
        XCTAssertNil(ResearchConfig.incompatibility(of: served(forms: bundledFormSpec())))
    }

    /// 配置绑定的任何一项材料与本机实际携带的不符 → 不采用（验收 A23）
    func testAnyMaterialMismatchClosesTheResearchPath() {
        XCTAssertEqual(ResearchConfig.incompatibility(of: served(consent: "consent-9.9")),
                       "consent_version")
        XCTAssertEqual(ResearchConfig.incompatibility(of: served(eligibility: "eligibility-1.0-draft")),
                       "eligibility_version")
        XCTAssertEqual(ResearchConfig.incompatibility(of: served(lexicon: "lex-other")),
                       "lexicon_version")
        XCTAssertEqual(ResearchConfig.incompatibility(of: served(appVersion: "0.0")),
                       "app_version")
        var forms = bundledFormSpec()
        forms["tone_needs_v1"]?["form_version"] = "tone_needs_v1-9.9"
        XCTAssertEqual(ResearchConfig.incompatibility(of: served(forms: forms)),
                       "survey_form:tone_needs_v1")
        forms = bundledFormSpec()
        forms["usability_short_v1"] = nil
        XCTAssertEqual(ResearchConfig.incompatibility(of: served(forms: forms)),
                       "survey_form:usability_short_v1")
    }

    /// 测试配置不得被正式用户采用
    func testTestManifestIsRejectedByANonTestClient() {
        XCTAssertEqual(ResearchConfig.incompatibility(of: served(isTest: true), isTestClient: false),
                       "test_manifest")
        XCTAssertNil(ResearchConfig.incompatibility(of: served(isTest: false), isTestClient: false))
    }

    func testInvertedWindowIsRejected() {
        let now = Date()
        XCTAssertEqual(ResearchConfig.incompatibility(of: served(start: now, end: now)), "window")
    }

    /// 配置过期：研究入口关闭，普通使用不受影响
    func testExpiredManifestIsNotOpen() {
        config.setAvailableForTesting(ResearchTestSupport.manifest(
            start: Date().addingTimeInterval(-7200), end: Date().addingTimeInterval(-3600)))
        XCTAssertFalse(config.isOpen())
        XCTAssertFalse(ResearchEnrollment.canJoinNow())
    }

    func testNotYetStartedManifestIsNotOpen() {
        config.setAvailableForTesting(ResearchTestSupport.manifest(
            start: Date().addingTimeInterval(3600), end: Date().addingTimeInterval(7200)))
        XCTAssertFalse(config.isOpen())
    }

    /// 研究入口需要：有账号、配置开放、状态允许邀请
    func testJoinEntryRequiresAccountOpenManifestAndInvitableState() {
        config.setAvailableForTesting(ResearchTestSupport.manifest())
        XCTAssertTrue(ResearchEnrollment.canJoinNow())

        ResearchStore.shared.activate(accountKey: nil)
        XCTAssertFalse(ResearchEnrollment.canJoinNow(), "没有账号就没有研究入口")

        ResearchTestSupport.enrolledAccount()
        XCTAssertFalse(ResearchEnrollment.canJoinNow(), "已参与的人不再看到邀请")
    }

    // MARK: - 刷新

    /// 刷新时报上本机的 App 版本与构建号——服务端据此只下发匹配的配置
    func testRefreshStatesAppVersionAndBuild() async {
        StubURLProtocol.install()
        StubURLProtocol.on("GET", "research/manifest/active") { .json(404, ["detail": "none"]) }
        await config.refresh()
        let q = StubURLProtocol.requests(to: "research/manifest/active").first?.query
        XCTAssertEqual(q?["appVersion"], AppEnvironment.appVersion)
        XCTAssertEqual(q?["build"], AppEnvironment.buildNumber)
        XCTAssertNotNil(q?["test"])
    }

    /// 服务端明确回答没有配置 → 清掉缓存，研究入口关闭，不报错给学习者
    func testServerSaysNoManifestClearsCache() async {
        config.setAvailableForTesting(ResearchTestSupport.manifest())
        StubURLProtocol.install()
        StubURLProtocol.on("GET", "research/manifest/active") { .json(404, ["detail": "none"]) }
        await config.refresh()
        XCTAssertNil(config.available)
    }

    /// 断网时保留缓存：离线不应让「开放」凭空消失（过期仍由时间挡住）
    func testOfflineRefreshKeepsCachedManifest() async {
        config.setAvailableForTesting(ResearchTestSupport.manifest())
        StubURLProtocol.install()        // 没有登记任何回答 = 断网
        await config.refresh()
        XCTAssertNotNil(config.available)
        XCTAssertTrue(config.isOpen())
    }

    /// 下发的配置与本机材料不匹配：视同没有配置
    func testMismatchedServedManifestIsNotAdopted() async {
        StubURLProtocol.install()
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        let end = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))
        StubURLProtocol.on("GET", "research/manifest/active") {
            .json(200, ["manifestID": "m", "studyID": "s", "collectionStartAt": start,
                        "collectionEndAt": end, "postTriggerCount": 5,
                        "consentVersion": "consent-some-other-text", "surveyVersion": "sv",
                        "isTest": true])
        }
        await config.refresh()
        XCTAssertNil(config.available)
        XCTAssertFalse(config.isOpen())
    }

    func testMatchingServedManifestIsAdopted() async {
        StubURLProtocol.install()
        let start = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        let end = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))
        StubURLProtocol.on("GET", "research/manifest/active") {
            .json(200, ["manifestID": "m-ok", "studyID": "s", "collectionStartAt": start,
                        "collectionEndAt": end, "postTriggerCount": 5,
                        "consentVersion": ResearchConsent.textVersion, "surveyVersion": "sv",
                        "eligibilityVersion": ResearchEligibility.version, "isTest": true])
        }
        await config.refresh()
        XCTAssertEqual(config.manifestID, "m-ok")
        XCTAssertTrue(config.isOpen())
    }
}
