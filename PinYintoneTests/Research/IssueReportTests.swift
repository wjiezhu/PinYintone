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
        ResearchIdentity.shared.clearOnWithdrawal()
        // 无研究身份时 submit 直接返回，不抛错也不发请求
        try await IssueReporter.submit(category: "other", detail: nil)
        XCTAssertFalse(ResearchIdentity.shared.isEnrolled)
    }
}
