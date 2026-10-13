import XCTest
@testable import PinYintone

/// 研究数据上报（需求 R05 / R07 / R08，验收 A11、A19、A21、A22）。
@MainActor
final class ResearchUploaderTests: XCTestCase {

    private var store: ResearchStore { .shared }
    private var uploader: ResearchUploader { .shared }

    override func setUp() {
        super.setUp()
        StubURLProtocol.install()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    @discardableResult
    private func queueAttempt(cancelled: Bool = true) -> UUID {
        let id = UUID()
        ResearchAttemptLog.shared.begin(attemptID: id, taskType: .fixedWord,
                                        lexemeVersionID: "lv", priorPracticeCount: nil)
        if cancelled {
            ResearchAttemptLog.shared.markCancelled(id)
        } else {
            ResearchAttemptLog.shared.markAnalyzing(id)
            ResearchAttemptLog.shared.markSucceeded(id, metric: 0.3, passed: true)
            ResearchAttemptLog.shared.markResultDisplayed(id)
        }
        return id
    }

    private func acceptEverything() {
        for path in ["research/attempts", "research/events", "research/advice"] {
            StubURLProtocol.on("POST", path) { StubURLProtocol.batchOK() }
        }
        StubURLProtocol.on("POST", "research/surveys") {
            .json(200, ["surveyInstanceID": "x", "alreadySubmitted": false,
                        "status": "complete", "updated": true])
        }
        StubURLProtocol.on("POST", "research/withdraw") { .json(200, ["status": "withdrawn"]) }
    }

    private func researchPaths() -> [String] {
        StubURLProtocol.requests.map { String($0.path.split(separator: "/").suffix(2).joined(separator: "/")) }
    }

    // MARK: - 顺序与外键依赖

    /// 身份与背景表确认 → 尝试 → 关联事件 → 建议
    func testUploadOrderIsBackgroundThenAttemptsThenEventsThenAdvice() async {
        ResearchTestSupport.enrolledAccount(backgroundAcked: false)
        let attempt = queueAttempt(cancelled: false)
        ResearchEventLog.shared.log(.feedbackDisplayed, attemptID: attempt, lexemeVersionID: "lv",
                                    payload: ["mode": "pitch_curve"])
        AdviceRequestLog.shared.record(advice: .make(result: nil, lexemeID: nil),
                                       attemptID: attempt, lexemeVersionID: "lv")
        acceptEverything()

        await uploader.flush()

        XCTAssertEqual(researchPaths(), ["research/surveys", "research/attempts",
                                         "research/events", "research/advice"])
        XCTAssertTrue(store.state.backgroundAcked)
        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty)
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty)
        XCTAssertTrue(AdviceRequestLog.shared.pending.isEmpty)
    }

    /// 背景表还没被服务端确认：尝试与事件先留在本机，不抢先上传
    func testNothingElseIsUploadedUntilBackgroundIsAcknowledged() async {
        ResearchTestSupport.enrolledAccount(backgroundAcked: false)
        queueAttempt()
        ResearchEventLog.shared.log(.historyOpened)
        StubURLProtocol.on("POST", "research/attempts") { StubURLProtocol.batchOK() }
        StubURLProtocol.on("POST", "research/events") { StubURLProtocol.batchOK() }
        // 问卷接口没有登记回答 = 断网

        await uploader.flush()

        XCTAssertEqual(researchPaths(), ["research/surveys"])
        XCTAssertEqual(ResearchAttemptLog.shared.pending.count, 1)
        XCTAssertEqual(ResearchEventLog.shared.pending.count, 1)
        XCTAssertFalse(store.state.backgroundAcked)
    }

    /// 尝试没传成，事件这一轮就不传（事件依赖尝试）
    func testEventsWaitWhenAttemptsFail() async {
        ResearchTestSupport.enrolledAccount()
        queueAttempt()
        ResearchEventLog.shared.log(.historyOpened)
        StubURLProtocol.on("POST", "research/attempts") { .json(503, ["detail": "busy"]) }
        StubURLProtocol.on("POST", "research/events") { StubURLProtocol.batchOK() }

        await uploader.flush()

        XCTAssertEqual(researchPaths(), ["research/attempts"])
        XCTAssertEqual(ResearchEventLog.shared.pending.count, 1)
    }

    // MARK: - 断网、超时、5xx：保留并原样重传（A11 / A19）

    func testTransportFailureKeepsQueueAndRetriesWithTheSameIDs() async {
        ResearchTestSupport.enrolledAccount()
        let id = queueAttempt()
        await uploader.flush()                       // 断网
        XCTAssertEqual(ResearchAttemptLog.shared.pending.map(\.attemptID), [id])

        acceptEverything()
        await uploader.flush()                       // 恢复联网
        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty)

        let sent = StubURLProtocol.requests(to: "research/attempts").compactMap {
            (($0.body["attempts"] as? [[String: Any]])?.first?["attemptID"] as? String)
        }
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(Set(sent), [id.uuidString], "重传必须复用同一个尝试编号")
    }

    func testServerErrorAndTimeoutAreRetriedNotDropped() async {
        ResearchTestSupport.enrolledAccount()
        queueAttempt()
        for reply in [StubURLProtocol.Reply.json(500, ["detail": "boom"]),
                      .json(429, ["detail": "slow down"]), .transportError(.timedOut)] {
            StubURLProtocol.on("POST", "research/attempts") { reply }
            await uploader.flush()
            XCTAssertEqual(ResearchAttemptLog.shared.pending.count, 1)
            XCTAssertEqual(store.deadLetterCount(queue: "attempts"), 0)
        }
    }

    // MARK: - 服务端明确拒收：不堵队列

    /// 个别记录被拒（窗口外等）：整批出队，被拒的计数留痕，后面的继续传
    func testRejectedRecordsLeaveTheQueueAndAreCounted() async {
        ResearchTestSupport.enrolledAccount()
        let bad = queueAttempt(), good = queueAttempt()
        ResearchEventLog.shared.log(.historyOpened)
        StubURLProtocol.on("POST", "research/attempts") {
            StubURLProtocol.batchOK(rejected: [["id": bad.uuidString, "reason": "outside_window"]])
        }
        StubURLProtocol.on("POST", "research/events") { StubURLProtocol.batchOK() }

        await uploader.flush()

        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty, "\(good) 也应已出队")
        XCTAssertEqual(store.deadLetterCount(queue: "attempts"), 1)
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty, "一条坏记录不应堵住事件")
    }

    /// 整批被 4xx 拒绝：重传也一样，记入拒收计数后出队
    func testWholeBatchRefusalDoesNotJamTheQueueForever() async {
        ResearchTestSupport.enrolledAccount()
        queueAttempt()
        ResearchEventLog.shared.log(.historyOpened)
        StubURLProtocol.on("POST", "research/attempts") { .json(400, ["detail": "未知状态"]) }
        StubURLProtocol.on("POST", "research/events") { StubURLProtocol.batchOK() }

        await uploader.flush()

        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty)
        XCTAssertEqual(store.deadLetterCount(queue: "attempts"), 1)
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty)
    }

    // MARK: - 服务端已停收

    /// 服务端已无有效同意（另一台设备上退出了、或账号被删）：端侧跟着停并清空
    func testServerSideWithdrawalStopsLocalCollection() async {
        ResearchTestSupport.enrolledAccount()
        queueAttempt()
        ResearchEventLog.shared.log(.historyOpened)
        StubURLProtocol.on("POST", "research/attempts") {
            .json(403, ["detail": "no_active_consent：该参与者当前无有效同意"])
        }
        await uploader.flush()

        XCTAssertEqual(store.state.participation, .withdrawn)
        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty)
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty)
        XCTAssertFalse(ResearchGate.shouldCollect())
        XCTAssertTrue(StubURLProtocol.requests(to: "research/events").isEmpty,
                      "被停收后不得继续发送")
    }

    /// 背景表复核不合格：端侧转为不纳入并清空
    func testServerSideExclusionStopsLocalCollection() async {
        ResearchTestSupport.enrolledAccount()
        queueAttempt()
        StubURLProtocol.on("POST", "research/attempts") {
            .json(403, ["detail": "not_eligible：该参与者不符合纳入条件"])
        }
        await uploader.flush()
        XCTAssertEqual(store.state.participation, .ineligible)
        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty)
    }

    // MARK: - 退出（A21）

    /// 离线退出后恢复联网：**先**同步退出，旧队列一条都不传
    func testOfflineWithdrawalSyncsFirstAndNeverUploadsTheOldQueue() async {
        ResearchTestSupport.enrolledAccount()
        queueAttempt()
        ResearchEventLog.shared.log(.historyOpened)

        ResearchEnrollment.withdraw()                 // 离线
        await uploader.flush()                        // 仍离线：指令保留
        XCTAssertNotNil(store.state.pendingWithdrawal)

        acceptEverything()
        await uploader.flush()                        // 恢复联网

        XCTAssertNil(store.state.pendingWithdrawal)
        let paths = researchPaths().filter { !$0.hasSuffix("withdraw") }
        XCTAssertTrue(paths.isEmpty, "退出后不得上传任何研究内容，却发了：\(paths)")
        let body = StubURLProtocol.requests(to: "research/withdraw").last?.body
        XCTAssertEqual(body?["participantID"] as? String, "participant-test")
    }

    /// 退出指令没同步成功之前，什么都不传
    func testPendingWithdrawalBlocksAllOtherUploads() async {
        ResearchTestSupport.enrolledAccount()
        queueAttempt()
        store.update { s in
            s.pendingWithdrawal = .init(participantID: "participant-test", consentVersion: "c",
                                        language: "fr", occurredAt: Date())
        }
        StubURLProtocol.on("POST", "research/attempts") { StubURLProtocol.batchOK() }
        await uploader.flush()
        XCTAssertTrue(StubURLProtocol.requests(to: "research/attempts").isEmpty)
        XCTAssertNotNil(store.state.pendingWithdrawal)
    }

    // MARK: - 窗口关闭后的补传（A22）

    func testQueuedDataIsStillUploadedAfterTheWindowCloses() async {
        ResearchTestSupport.enrolledAccount()
        let id = queueAttempt()
        store.update { $0.windowEnd = Date().addingTimeInterval(-5) }      // 窗口刚关
        XCTAssertFalse(ResearchGate.shouldCollect())
        acceptEverything()

        await uploader.flush()

        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty, "窗口内产生的记录应当补传")
        let sent = (StubURLProtocol.requests(to: "research/attempts").first?
            .body["attempts"] as? [[String: Any]])?.first?["attemptID"] as? String
        XCTAssertEqual(sent, id.uuidString)
    }

    // MARK: - 账号切换

    func testNotEnrolledMeansNoUpload() async {
        ResearchTestSupport.freshAccount()
        acceptEverything()
        await uploader.flush()
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    /// 上传途中换了账号：A 的回执不能落到 B 的状态上
    func testAccountSwitchDuringUploadDoesNotTouchTheNewAccount() async {
        let a = ResearchTestSupport.enrolledAccount()
        let id = queueAttempt()
        var other = ""
        StubURLProtocol.on("POST", "research/attempts") {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { other = ResearchTestSupport.enrolledAccount() }
            }
            return StubURLProtocol.batchOK()
        }
        await uploader.flush()

        XCTAssertEqual(store.accountKey, other)
        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty)      // B 本来就是空的
        store.activate(accountKey: a)
        XCTAssertEqual(ResearchAttemptLog.shared.pending.map(\.attemptID), [id],
                       "A 的记录没有被确认出队（回执到达时已不是 A）——下次 A 登录再传，服务端按编号去重")
        store.purgeCurrentAccount()
        store.activate(accountKey: other)
    }

    // MARK: - 问卷（A11 / A12）

    /// 提交时断网：答案留在本机，显示「已保存，等待联网提交」；恢复后恰好一份
    func testSurveySubmittedOfflineIsKeptThenUploadedOnceWithTheSameInstance() async throws {
        ResearchTestSupport.enrolledAccount()
        let invited = try XCTUnwrap(SurveyCenter.invite(SurveyCenter.postKey))
        let answers = [SurveyAnswer(questionID: "POST01", state: .answered,
                                    optionCodes: ["agree"], textValue: nil, answeredAt: Date())]
        SurveyCenter.submit(SurveyCenter.postKey, answers: answers)
        await uploader.flush()                                       // 断网

        var record = try XCTUnwrap(SurveyCenter.record(SurveyCenter.postKey))
        XCTAssertEqual(SurveyDisplayStatus(record), .savedWaitingForNetwork,
                       "服务端没确认之前不能显示已提交")
        XCTAssertEqual(record.answers, answers)

        StubURLProtocol.on("POST", "research/surveys") {
            .json(200, ["surveyInstanceID": invited.instanceID.uuidString,
                        "alreadySubmitted": false, "status": "complete", "updated": true])
        }
        await uploader.flush()
        record = try XCTUnwrap(SurveyCenter.record(SurveyCenter.postKey))
        XCTAssertEqual(SurveyDisplayStatus(record), .submitted)

        let sentSoFar = StubURLProtocol.requests(to: "research/surveys").count
        await uploader.flush()                                       // 再跑一轮
        XCTAssertEqual(StubURLProtocol.requests(to: "research/surveys").count, sentSoFar,
                       "服务端确认之后不应再重发")

        let all = StubURLProtocol.requests(to: "research/surveys")
        let ids = Set(all.compactMap { $0.body["surveyInstanceID"] as? String })
        XCTAssertEqual(ids, [invited.instanceID.uuidString], "从邀请到提交始终是同一个实例")
        let invitedAt = Set(all.compactMap { $0.body["invitedAt"] as? String })
        XCTAssertEqual(invitedAt.count, 1, "重试不得改变邀请时间")
    }

    /// 同一账号已在另一台设备上填完：以服务端为准，本机不再让人重填
    func testSurveyAlreadyCompletedElsewhereIsAdoptedLocally() async throws {
        ResearchTestSupport.enrolledAccount()
        SurveyCenter.invite(SurveyCenter.postKey)
        StubURLProtocol.on("POST", "research/surveys") {
            .json(200, ["surveyInstanceID": "from-other-device", "alreadySubmitted": true,
                        "status": "complete", "updated": false])
        }
        await uploader.flush()
        let record = try XCTUnwrap(SurveyCenter.record(SurveyCenter.postKey))
        XCTAssertEqual(record.status, .complete)
        XCTAssertFalse(record.isResumable)
        XCTAssertTrue(SurveyCenter.resumable(in: store.state).isEmpty)
    }

    /// 服务端拒收（如窗口已关闭）：不再重试，也**不**显示成已提交
    func testRejectedSurveyIsNotShownAsSubmitted() async throws {
        ResearchTestSupport.enrolledAccount()
        SurveyCenter.invite(SurveyCenter.postKey)
        SurveyCenter.decline(SurveyCenter.postKey)
        StubURLProtocol.on("POST", "research/surveys") {
            .json(409, ["detail": "outside_window：问卷不是在采集窗口内完成的"])
        }
        await uploader.flush()
        let record = try XCTUnwrap(SurveyCenter.record(SurveyCenter.postKey))
        XCTAssertEqual(record.rejectedReason, "outside_window")
        XCTAssertEqual(SurveyDisplayStatus(record), .notAccepted)
        let before = StubURLProtocol.requests(to: "research/surveys").count
        await uploader.flush()
        XCTAssertEqual(StubURLProtocol.requests(to: "research/surveys").count, before)
    }
}
