import XCTest
@testable import PinYintone

@MainActor
final class ResearchIdentityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ResearchIdentity.shared.clearOnWithdrawal()
        ResearchEventLog.shared.clearPendingOnWithdrawal()
    }
    override func tearDown() {
        ResearchIdentity.shared.clearOnWithdrawal()
        super.tearDown()
    }

    func testNotEnrolledByDefault() {
        XCTAssertFalse(ResearchIdentity.shared.isEnrolled)
        XCTAssertNil(ResearchIdentity.shared.participantID)
    }

    func testStoreAndPersist() {
        ResearchIdentity.shared.store(participantID: "p-uuid", manifestID: "m1", studyID: "s1")
        XCTAssertTrue(ResearchIdentity.shared.isEnrolled)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "pt_research_participant_id"),
                       "p-uuid", "须落盘，重启后仍是同一研究编号")
    }

    func testWithdrawalClearsLocalIdentity() {
        ResearchIdentity.shared.store(participantID: "p-uuid", manifestID: "m1", studyID: "s1")
        ResearchIdentity.shared.clearOnWithdrawal()
        XCTAssertFalse(ResearchIdentity.shared.isEnrolled)
        XCTAssertNil(UserDefaults.standard.string(forKey: "pt_research_participant_id"))
    }

    /// 未纳入研究时 flush 不得尝试上报
    func testFlushIsNoOpWhenNotEnrolled() async {
        let n = await ResearchUploader.shared.flush()
        XCTAssertEqual(n, 0)
    }
}
