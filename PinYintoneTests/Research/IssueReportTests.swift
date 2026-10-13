import XCTest
@testable import PinYintone

@MainActor
final class IssueReportTests: XCTestCase {

    /// 六个类别在四种语言下都有译文，且与 POST04 同一组编码
    func testCategoryCopyInAllLanguages() throws {
        let cats = ["cannot_find_action", "recording_failed", "analysis_failed",
                    "app_crashed", "unclear_feedback", "other"]
        for lang in ["zh-Hans", "en", "fr", "ar"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for c in cats {
                let key = "issue_cat_\(c)"
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil),
                                  key, "\(lang) 缺少 \(key)")
            }
        }
    }

    /// 未纳入研究时不得调用研究接口——非研究用户的反馈不进研究表（字典 §12）
    func testNonEnrolledUserDoesNotHitResearchEndpoint() async throws {
        ResearchTestSupport.freshAccount()
        StubURLProtocol.install()
        defer { ResearchTestSupport.tearDown() }
        try await IssueReporter.submit(category: "other", detail: nil)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "没有研究身份时不应发出任何请求")
    }

    /// 窗口关闭后同样不写研究表：问题报告与其它研究写入同一道门禁（R08）
    func testNoResearchReportOutsideCollectionWindow() async throws {
        ResearchTestSupport.enrolledAccount(windowStart: Date().addingTimeInterval(-7200),
                                            windowEnd: Date().addingTimeInterval(-3600))
        StubURLProtocol.install()
        defer { ResearchTestSupport.tearDown() }
        try await IssueReporter.submit(category: "other", detail: "x")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    /// 网络失败后用户再点一次提交：复用同一个 report_id，服务端只会有一份
    func testRetryReusesTheSameReportID() async throws {
        ResearchTestSupport.enrolledAccount()
        StubURLProtocol.install()
        defer { ResearchTestSupport.tearDown() }
        do {
            try await IssueReporter.submit(category: "recording_failed", detail: "按了没反应")
            XCTFail("断网时应当抛错")
        } catch {}
        StubURLProtocol.on("POST", "research/issues") {
            .json(200, ["reportID": "x", "alreadyReceived": false])
        }
        try await IssueReporter.submit(category: "recording_failed", detail: "按了没反应")
        let ids = StubURLProtocol.requests(to: "research/issues")
            .compactMap { $0.body["reportID"] as? String }
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 1, "重试必须复用同一个 report_id")
    }
}
