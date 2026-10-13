import XCTest
@testable import PinYintone

/// 研究状态按账号隔离并落盘（需求 R08、验收 A20）。
@MainActor
final class ResearchStoreTests: XCTestCase {

    private var store: ResearchStore { .shared }
    private var accounts: [String] = []

    override func tearDown() {
        for key in accounts {
            store.activate(accountKey: key)
            store.purgeCurrentAccount()
        }
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    private func account(_ name: String) -> String {
        let key = "store-test-\(name)-\(UUID().uuidString)"
        accounts.append(key)
        return key
    }

    func testNoAccountMeansNoResearchStateAndNoCollection() {
        store.activate(accountKey: nil)
        store.update { $0.participation = .enrolled }      // 没有账号：写不进去
        XCTAssertEqual(store.state.participation, .notAsked)
        XCTAssertFalse(ResearchGate.shouldCollect())
        XCTAssertFalse(ResearchEventLog.shared.log(.historyOpened))
    }

    /// 切账号后，上一个人的身份、同意、问卷与计数都不带过来
    func testSwitchingAccountDoesNotCarryIdentityConsentOrCounts() {
        let a = account("a"), b = account("b")
        store.activate(accountKey: a)
        store.update { s in
            s.participation = .enrolled
            s.eligibility = "eligible"
            s.participantID = "participant-A"
            s.manifestID = "m"
            s.qualifyingCount = 4
            s.countedAttemptIDs = ["x"]
            s.backgroundDraft = SurveyDraft(index: 2, selections: ["B01": ["adult"]])
        }

        store.activate(accountKey: b)
        XCTAssertEqual(store.state, ResearchState(), "新账号必须是一份空状态")
        XCTAssertNil(store.state.participantID)
        XCTAssertEqual(store.state.qualifyingCount, 0)
        XCTAssertNil(store.state.backgroundDraft)

        // 切回去：A 的状态原样还在
        store.activate(accountKey: a)
        XCTAssertEqual(store.state.participantID, "participant-A")
        XCTAssertEqual(store.state.qualifyingCount, 4)
        XCTAssertEqual(store.state.backgroundDraft?.index, 2)
    }

    /// 待传队列同样按账号隔离：B 登录后不会把 A 的尝试当成自己的发出去
    func testPendingQueuesAreNotSharedAcrossAccounts() {
        let a = ResearchTestSupport.enrolledAccount()
        accounts.append(a)
        let id = UUID()
        ResearchAttemptLog.shared.begin(attemptID: id, taskType: .fixedWord,
                                        lexemeVersionID: "lv", priorPracticeCount: nil)
        ResearchAttemptLog.shared.markCancelled(id)
        XCTAssertTrue(ResearchEventLog.shared.log(.historyOpened))
        XCTAssertEqual(ResearchAttemptLog.shared.pending.count, 1)

        let b = ResearchTestSupport.enrolledAccount()
        accounts.append(b)
        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty, "B 看到了 A 的待传尝试")
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty, "B 看到了 A 的待传事件")

        store.activate(accountKey: a)
        XCTAssertEqual(ResearchAttemptLog.shared.pending.map(\.attemptID), [id],
                       "A 重新登录后，它合法产生的待传数据还在")
        XCTAssertEqual(ResearchEventLog.shared.pending.count, 1)
    }

    /// 状态落盘：重启（重新加载同一账号）后参与状态与**资格**都还在。
    /// 此前资格只存内存，重启即变回 pending，已纳入的人从此不再产生研究数据。
    func testEnrollmentAndEligibilitySurviveRelaunch() {
        let key = ResearchTestSupport.enrolledAccount()
        accounts.append(key)
        XCTAssertTrue(ResearchGate.shouldCollect())

        store.activate(accountKey: nil)          // 模拟进程结束
        store.activate(accountKey: key)          // 再次启动
        XCTAssertEqual(store.state.eligibilityOutcome, .eligible)
        XCTAssertTrue(ResearchGate.shouldCollect(), "重启后已纳入者应继续采集")
    }

    func testPurgeRemovesStateAndQueues() {
        let key = ResearchTestSupport.enrolledAccount()
        XCTAssertTrue(ResearchEventLog.shared.log(.historyOpened))
        store.purgeCurrentAccount()
        store.activate(accountKey: key)
        accounts.append(key)
        XCTAssertEqual(store.state.participation, .notAsked)
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty)
    }

    func testStudentAccountKeyPrefersAppleIDSoDevicesShareNothingByAccident() {
        var p = ResearchTestSupport.profile(appleID: "apple-\(UUID().uuidString)")
        store.activate(for: p)
        let key = store.accountKey
        XCTAssertEqual(key, p.appleUserID)
        p.role = .teacher
        store.activate(for: p)
        XCTAssertNil(store.accountKey, "教师账号没有研究状态")
        if let key { accounts.append(key) }
    }

    /// 旧版把研究状态放在全局、不分账号。升级后第一个登录的账号继承它，
    /// 随后全局键被清掉——第二个账号看不到。
    func testLegacyGlobalStateMigratesOnceToTheFirstAccount() {
        let d = UserDefaults.standard
        d.set("granted", forKey: "pt_research_consent_state")
        d.set("legacy-participant", forKey: "pt_research_participant_id")
        d.set("legacy-manifest", forKey: "pt_research_manifest_id")
        d.set(3, forKey: "pt_research_qualifying_attempts")
        defer {
            ["pt_research_consent_state", "pt_research_participant_id",
             "pt_research_manifest_id", "pt_research_qualifying_attempts"]
                .forEach { d.removeObject(forKey: $0) }
        }
        let first = account("legacy-first"), second = account("legacy-second")
        store.activate(accountKey: first)
        XCTAssertEqual(store.state.participation, .enrolled)
        XCTAssertEqual(store.state.participantID, "legacy-participant")
        XCTAssertEqual(store.state.qualifyingCount, 3)
        XCTAssertNil(d.string(forKey: "pt_research_participant_id"), "全局键应已清除")

        store.activate(accountKey: second)
        XCTAssertEqual(store.state.participation, .notAsked)
    }

    func testLegacyConsentWithoutIdentityIsNotPromotedToEnrolled() {
        let d = UserDefaults.standard
        d.set("granted", forKey: "pt_research_consent_state")
        defer { d.removeObject(forKey: "pt_research_consent_state") }
        store.activate(accountKey: account("legacy-consent-only"))
        XCTAssertEqual(store.state.participation, .consentedPending,
                       "本地同意不等于已参加")
        XCTAssertFalse(ResearchGate.shouldCollect())
    }
}
