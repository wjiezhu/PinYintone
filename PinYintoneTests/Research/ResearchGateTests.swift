import XCTest
@testable import PinYintone

@MainActor
final class ResearchGateTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private func window(from start: Date) -> ResearchGate.CollectionWindow {
        .init(start: start, end: start.addingTimeInterval(14 * 86_400))
    }

    func testWindowIsHalfOpen() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let w = window(from: start)
        XCTAssertTrue(w.contains(start), "左闭：起点应included")
        XCTAssertTrue(w.contains(start.addingTimeInterval(13.99 * 86_400)))
        XCTAssertFalse(w.contains(start.addingTimeInterval(14 * 86_400)),
                       "右开：第 14 天整点应排除")
        XCTAssertFalse(w.contains(start.addingTimeInterval(-1)))
    }

    func testNoCollectionWithoutConfiguredWindow() {
        ResearchConsent.shared.grant(textVersion: "t", language: "zh")
        XCTAssertFalse(ResearchGate.shouldCollect(eligibility: .eligible, window: nil),
                       "窗口未配置时不得采集，不猜测")
    }

    func testIneligibleNeverCollects() {
        ResearchConsent.shared.grant(textVersion: "t", language: "zh")
        let w = window(from: Date().addingTimeInterval(-day))
        for outcome: ResearchEligibility.Outcome in [.pending, .excluded(.age), .excluded(.nationality)] {
            XCTAssertFalse(ResearchGate.shouldCollect(eligibility: outcome, window: w))
        }
    }

    func testWithdrawalStopsCollectionImmediately() {
        let w = window(from: Date().addingTimeInterval(-day))
        ResearchConsent.shared.grant(textVersion: "t", language: "zh")
        XCTAssertTrue(ResearchGate.shouldCollect(eligibility: .eligible, window: w))

        ResearchConsent.shared.withdraw()
        XCTAssertFalse(ResearchGate.shouldCollect(eligibility: .eligible, window: w),
                       "撤回后端侧必须立即停止采集，不等服务端确认")
    }

    func testDeclineIsRememberedAndBlocksCollection() {
        ResearchConsent.shared.decline()
        XCTAssertEqual(ResearchConsent.shared.state, .declined)
        XCTAssertFalse(ResearchConsent.shared.allowsResearchCollection)
    }

    func testConsentRecordsVersionAndLanguageActuallyShown() {
        ResearchConsent.shared.grant(textVersion: "consent-1.0-unpublished", language: "ar")
        XCTAssertEqual(ResearchConsent.shared.grantedVersion, "consent-1.0-unpublished")
        XCTAssertEqual(ResearchConsent.shared.grantedLanguage, "ar",
                       "须记录用户实际看到的文本版本与语言")
    }
}
