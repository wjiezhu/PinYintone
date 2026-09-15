import XCTest
@testable import PinYintone

@MainActor
final class ResearchConfigTests: XCTestCase {

    private let keys = ["pt_research_manifest_config_id",
                        "pt_research_window_start", "pt_research_window_end"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        ResearchEventLog.shared.window = nil
    }
    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    /// 没有配置时不得纳入，也不得猜一个
    func testNoManifestMeansNoEnrollment() {
        XCTAssertNil(ResearchConfig.shared.manifestID)
        XCTAssertNil(ResearchConfig.shared.window)
        XCTAssertNil(ResearchEnrollment.manifestID,
                     "未下发配置时 manifestID 必须为 nil，不能有默认值")
    }

    /// 窗口只有起止都在时才成立——半套缓存不得被当成有效窗口
    func testPartialWindowCacheIsNotUsable() {
        UserDefaults.standard.set(Date(), forKey: "pt_research_window_start")
        XCTAssertNil(ResearchConfig.shared.window, "只有开始时间不构成窗口")
    }

    /// 缓存的窗口要能在联网前就打开门禁（离线不应让已纳入者停止采集）
    func testCachedWindowAppliedBeforeNetwork() {
        let start = Date().addingTimeInterval(-60)
        let end = Date().addingTimeInterval(3600)
        let d = UserDefaults.standard
        d.set("m-cached", forKey: "pt_research_manifest_config_id")
        d.set(start, forKey: "pt_research_window_start")
        d.set(end, forKey: "pt_research_window_end")

        ResearchConfig.shared.applyCachedWindow()
        XCTAssertNotNil(ResearchEventLog.shared.window)
        XCTAssertEqual(ResearchEnrollment.manifestID, "m-cached")
    }

    /// 窗口外即便有配置也不采集
    func testOutsideWindowBlocksCollection() {
        let d = UserDefaults.standard
        d.set("m1", forKey: "pt_research_manifest_config_id")
        d.set(Date().addingTimeInterval(-7200), forKey: "pt_research_window_start")
        d.set(Date().addingTimeInterval(-3600), forKey: "pt_research_window_end")
        ResearchConfig.shared.applyCachedWindow()

        ResearchConsent.shared.grant(textVersion: "c1", language: "zh")
        ResearchEventLog.shared.eligibility = .eligible
        defer { ResearchConsent.shared.withdraw() }

        XCTAssertFalse(ResearchEventLog.shared.log(.historyOpened),
                       "采集窗口外不得产生研究事件")
    }
}
