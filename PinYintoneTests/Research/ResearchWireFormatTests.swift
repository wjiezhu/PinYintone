import XCTest
@testable import PinYintone

/// App **实际发出的** JSON 与服务端字段逐项对照。
///
/// 这组测试存在的原因：操作事件曾按 Swift 属性名原样编码，事件名发成了 `name`，
/// 而服务端要的是 `eventName`——真实 App 的每一条事件都被 422 拒收。
/// 接口验证脚本自己拼的请求体字段是对的，所以脚本全绿、App 全丢。
/// 下面各字段名与 backend/app/schemas.py 的 DTO 一一对应；改任一端都要改这里。
@MainActor
final class ResearchWireFormatTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.install()
        for path in ["research/attempts", "research/events", "research/advice"] {
            StubURLProtocol.on("POST", path) { StubURLProtocol.batchOK() }
        }
        StubURLProtocol.on("POST", "research/surveys") {
            .json(200, ["surveyInstanceID": "x", "alreadySubmitted": false,
                        "status": "complete", "updated": true])
        }
        ResearchTestSupport.enrolledAccount()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    private func isISO8601WithZone(_ value: Any?) -> Bool {
        guard let s = value as? String else { return false }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) != nil
    }

    func testEventBatchMatchesServerDTO() async throws {
        let attempt = UUID()
        ResearchAttemptLog.shared.begin(attemptID: attempt, taskType: .fixedWord,
                                        lexemeVersionID: "lv-1", priorPracticeCount: nil)
        ResearchAttemptLog.shared.markAnalyzing(attempt)
        ResearchAttemptLog.shared.markSucceeded(attempt, metric: 0.42, passed: true)
        ResearchAttemptLog.shared.markResultDisplayed(attempt)
        ResearchEventLog.shared.log(.feedbackDisplayed, attemptID: attempt,
                                    lexemeVersionID: "lv-1", payload: ["mode": "pitch_curve"])
        await ResearchUploader.shared.flush()

        let body = try XCTUnwrap(StubURLProtocol.requests(to: "research/events").first?.body)
        XCTAssertEqual(body["participantID"] as? String, "participant-test")
        XCTAssertEqual(body["manifestID"] as? String, "manifest-test")
        let event = try XCTUnwrap((body["events"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(event.keys), ["eventID", "sessionID", "attemptID", "lexemeVersionID",
                                         "eventName", "occurredAt", "sessionElapsedMs",
                                         "uiLanguage", "payload"])
        XCTAssertEqual(event["eventName"] as? String, "feedback_displayed",
                       "事件名必须在 eventName 字段里")
        XCTAssertNil(event["name"], "不得再用属性名 name 上报")
        XCTAssertEqual(event["attemptID"] as? String, attempt.uuidString)
        XCTAssertEqual((event["payload"] as? [String: String])?["mode"], "pitch_curve")
        XCTAssertTrue(isISO8601WithZone(event["occurredAt"]), "时间必须是带时区的 ISO8601 字符串")
        XCTAssertTrue(["zh", "en", "fr", "ar"].contains(event["uiLanguage"] as? String ?? ""))
    }

    func testAttemptBatchMatchesServerDTO() async throws {
        let first = UUID(), second = UUID()
        ResearchAttemptLog.shared.begin(attemptID: first, taskType: .fixedWord,
                                        lexemeVersionID: "lv-1", priorPracticeCount: nil)
        ResearchAttemptLog.shared.markAnalyzing(first)
        ResearchAttemptLog.shared.markFailed(first, status: .analysisFailed, error: .noSignal)
        ResearchAttemptLog.shared.begin(attemptID: second, taskType: .fixedWord,
                                        lexemeVersionID: "lv-1", priorPracticeCount: nil,
                                        retryOf: first)
        ResearchAttemptLog.shared.markAnalyzing(second)
        ResearchAttemptLog.shared.markSucceeded(second, metric: 0.61, passed: false)
        ResearchAttemptLog.shared.markResultDisplayed(second)
        await ResearchUploader.shared.flush()

        let body = try XCTUnwrap(StubURLProtocol.requests(to: "research/attempts").first?.body)
        let attempts = try XCTUnwrap(body["attempts"] as? [[String: Any]])
        XCTAssertEqual(attempts.count, 2)
        let allowed: Set<String> = ["attemptID", "sessionID", "taskType", "lexemeVersionID",
                                    "retryOfAttemptID", "priorPracticeCount", "startedAt", "status",
                                    "finishedAt", "recordingDurationMs", "analysisDurationMs",
                                    "signalStatus", "metricValue", "passed", "errorCode",
                                    "resultDisplayedAt", "timeQuality"]
        for a in attempts {
            XCTAssertTrue(Set(a.keys).isSubset(of: allowed), "多出字段：\(Set(a.keys).subtracting(allowed))")
            for required in ["attemptID", "sessionID", "taskType", "startedAt", "status",
                             "signalStatus", "timeQuality"] {
                XCTAssertNotNil(a[required], "缺 \(required)")
            }
            XCTAssertTrue(isISO8601WithZone(a["startedAt"]))
        }
        let failed = try XCTUnwrap(attempts.first { $0["attemptID"] as? String == first.uuidString })
        XCTAssertEqual(failed["status"] as? String, "analysis_failed")
        XCTAssertEqual(failed["errorCode"] as? String, "no_signal")
        // 技术失败：没有成绩。字段要么不出现，要么是 null——绝不是 0
        XCTAssertTrue(failed["metricValue"] == nil || failed["metricValue"] is NSNull)
        XCTAssertTrue(failed["passed"] == nil || failed["passed"] is NSNull)

        let ok = try XCTUnwrap(attempts.first { $0["attemptID"] as? String == second.uuidString })
        XCTAssertEqual(ok["status"] as? String, "succeeded")
        XCTAssertEqual(ok["taskType"] as? String, "fixed_word")
        XCTAssertEqual(ok["retryOfAttemptID"] as? String, first.uuidString)
        XCTAssertEqual(ok["passed"] as? Bool, false, "低分的有效结果：passed=false，不是失败状态")
        XCTAssertEqual(ok["metricValue"] as? Double ?? -1, 0.61, accuracy: 0.0001)
        XCTAssertTrue(isISO8601WithZone(ok["resultDisplayedAt"]))
    }

    func testSurveyUploadMatchesServerDTO() async throws {
        let record = try XCTUnwrap(SurveyCenter.invite(SurveyCenter.postKey))
        SurveyCenter.submit(SurveyCenter.postKey, answers: [
            SurveyAnswer(questionID: "POST01", state: .answered, optionCodes: ["agree"],
                         textValue: nil, answeredAt: Date()),
            SurveyAnswer(questionID: "POST02", state: .skipped, optionCodes: nil,
                         textValue: nil, answeredAt: Date()),
            SurveyAnswer(questionID: "POST03", state: .notAnswered, optionCodes: nil,
                         textValue: nil, answeredAt: nil)])
        await ResearchUploader.shared.flush()

        let body = try XCTUnwrap(StubURLProtocol.requests(to: "research/surveys").last {
            (($0.body["outcome"] as? [String: Any])?["status"] as? String) == "partial"
        }?.body)
        XCTAssertEqual(Set(body.keys), ["participantID", "manifestID", "surveyInstanceID",
                                        "invitedAt", "outcome", "timingClass",
                                        "qualifyingAttemptsAtInvite"])
        XCTAssertEqual(body["surveyInstanceID"] as? String, record.instanceID.uuidString)
        XCTAssertEqual(body["timingClass"] as? String, "after_practice")
        XCTAssertTrue(isISO8601WithZone(body["invitedAt"]))
        let outcome = try XCTUnwrap(body["outcome"] as? [String: Any])
        let form = try XCTUnwrap(SurveyFormLoader.bundled[SurveyCenter.postKey])
        XCTAssertEqual(outcome["formKey"] as? String, "usability_short_v1")
        XCTAssertEqual(outcome["formVersion"] as? String, form.formVersion)
        XCTAssertEqual(outcome["translationVersion"] as? String, form.translationVersion)
        XCTAssertTrue(["zh", "en", "fr", "ar"].contains(outcome["language"] as? String ?? ""))
        XCTAssertTrue(isISO8601WithZone(outcome["submittedAt"]))
        let answers = try XCTUnwrap(outcome["answers"] as? [[String: Any]])
        XCTAssertEqual(answers.map { $0["state"] as? String },
                       ["answered", "skipped", "not_answered"])
        XCTAssertEqual(answers[0]["questionID"] as? String, "POST01")
        XCTAssertEqual(answers[0]["optionCodes"] as? [String], ["agree"])
    }

    /// 非最终状态（已邀请、稍后填写）不带答案、不带提交时间
    func testNonFinalSurveyStateCarriesNoAnswers() async throws {
        SurveyCenter.invite(SurveyCenter.postKey)
        SurveyCenter.saveDraft(SurveyCenter.postKey,
                               SurveyDraft(index: 1, selections: ["POST01": ["agree"]]))
        SurveyCenter.deferSurvey(SurveyCenter.postKey)
        await ResearchUploader.shared.flush()
        let outcome = try XCTUnwrap(StubURLProtocol.requests(to: "research/surveys").last?
            .body["outcome"] as? [String: Any])
        XCTAssertEqual(outcome["status"] as? String, "deferred")
        XCTAssertEqual((outcome["answers"] as? [Any])?.count, 0, "草稿不上传")
        XCTAssertTrue(outcome["submittedAt"] == nil || outcome["submittedAt"] is NSNull)
    }

    func testAdviceBatchMatchesServerDTO() async throws {
        let attempt = UUID()
        ResearchAttemptLog.shared.begin(attemptID: attempt, taskType: .fixedWord,
                                        lexemeVersionID: "lv-1", priorPracticeCount: nil)
        ResearchAttemptLog.shared.markAnalyzing(attempt)
        ResearchAttemptLog.shared.markSucceeded(attempt, metric: 0.8, passed: false)
        ResearchAttemptLog.shared.markResultDisplayed(attempt)
        let result = FeedbackResult(dtwScore: 0.8, grade: .fail, attemptNumber: 1, segments: [])
        AdviceRequestLog.shared.record(advice: .make(result: result, lexemeID: nil),
                                       attemptID: attempt, lexemeVersionID: "lv-1")
        await ResearchUploader.shared.flush()

        let body = try XCTUnwrap(StubURLProtocol.requests(to: "research/advice").first?.body)
        let request = try XCTUnwrap((body["requests"] as? [[String: Any]])?.first)
        for required in ["requestID", "attemptID", "requestedAt", "status", "sourceType",
                         "evidenceCodes", "evidenceSnapshot"] {
            XCTAssertNotNil(request[required], "缺 \(required)")
        }
        XCTAssertEqual(request["attemptID"] as? String, attempt.uuidString)
        XCTAssertEqual(request["sourceType"] as? String, "rule_feedback")
        XCTAssertEqual(request["evidenceCodes"] as? [String], ["overall_metric"])
        // 服务端只接受这几个证据快照字段
        let snapshot = try XCTUnwrap(request["evidenceSnapshot"] as? [String: String])
        XCTAssertTrue(Set(snapshot.keys).isSubset(of: ["signal_status", "metric_name",
                                                       "metric_value", "gate"]))
        XCTAssertTrue(["zh", "en", "fr", "ar"].contains(request["outputLanguage"] as? String ?? ""))
    }

    /// 研究接口的时间一律是带时区的 ISO8601 字符串，不是 iOS 默认的 2001 基准秒数
    func testResearchDatesAreNeverEncodedAsNumbers() throws {
        let data = try ResearchJSON.encoder.encode(["t": Date()])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object["t"] is String)
        XCTAssertTrue(isISO8601WithZone(object["t"]))
    }
}
