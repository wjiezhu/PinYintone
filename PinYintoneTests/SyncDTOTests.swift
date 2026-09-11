import XCTest
@testable import PinYintone

final class SyncDTOTests: XCTestCase {

    func testTrainingSessionDTOEncodesExpectedKeys() throws {
        let dto = TrainingSessionDTO(
            id: "abc", deviceID: "dev", classCode: "123456", role: "student",
            groupAssignment: "n/a", lexemeID: "paobu", dtwScore: 0.42,
            grade: "good", attemptNumber: 2, timestamp: "2026-05-20T10:00:00Z",
            referenceType: "tts", voicedFrameCount: 42,
            qualityFlag: false, referenceSwitchedDuringAttempt: false,
            phase: "training", wordSetID: "set2",
            presentationOrder: "dynamicF0_first", assessmentSetVersion: nil,
            feedbackMode: nil, resultStatus: "valid_result",
            failureReason: nil, schemaVersion: RecordSchema.version,
            appVersion: "1.2 (9)"
        )
        let data = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["lexemeID"] as? String, "paobu")
        XCTAssertEqual(json["groupAssignment"] as? String, "n/a")
        XCTAssertEqual(json["attemptNumber"] as? Int, 2)
        // 诊断埋点字段应随记录一并上报（P1-3）
        XCTAssertEqual(json["referenceType"] as? String, "tts")
        XCTAssertEqual(json["voicedFrameCount"] as? Int, 42)
        XCTAssertEqual(json["referenceSwitchedDuringAttempt"] as? Bool, false)
        // 研究字段应随记录一并上报（升级需求 §3.1 / §3.2）
        XCTAssertEqual(json["phase"] as? String, "training")
        XCTAssertEqual(json["wordSetID"] as? String, "set2")
        XCTAssertEqual(json["presentationOrder"] as? String, "dynamicF0_first")
        // 记录语义与版本（升级需求 §6.1 / §6.2）
        XCTAssertNil(json["feedbackMode"], "已取消 A/B：新记录不再写反馈条件")
        XCTAssertEqual(json["resultStatus"] as? String, "valid_result")
        XCTAssertEqual(json["schemaVersion"] as? Int, RecordSchema.version)
        XCTAssertEqual(json["appVersion"] as? String, "1.2 (9)")
    }


    func testAssessmentRecordCarriesSetVersionAndNoCondition() throws {
        // 裸测记录：无反馈条件（"n/a"），但必须带测试词集版本，否则跨版本不可比
        let dto = TrainingSessionDTO(
            id: "a1", deviceID: "dev", classCode: nil, role: "student",
            groupAssignment: "n/a", lexemeID: "sushe", dtwScore: 0.61,
            grade: "fail", attemptNumber: 1, timestamp: "2026-05-20T10:00:00Z",
            referenceType: "tts", voicedFrameCount: 30,
            qualityFlag: false, referenceSwitchedDuringAttempt: false,
            phase: "pretest", wordSetID: "assessment",
            presentationOrder: "staticColor_first",
            assessmentSetVersion: AssessmentSet.version,
            feedbackMode: nil, resultStatus: "quality_flagged",
            failureReason: nil, schemaVersion: RecordSchema.version,
            appVersion: "1.2 (9)"
        )
        let back = try JSONDecoder().decode(
            TrainingSessionDTO.self, from: JSONEncoder().encode(dto))
        XCTAssertEqual(back.phase, "pretest")
        XCTAssertEqual(back.groupAssignment, "n/a")
        XCTAssertEqual(back.assessmentSetVersion, AssessmentSet.version)
    }

    func testNilClassCodeEncodesAndDecodes() throws {
        // 游客（classCode = nil）应可编解码（论文：未绑定班级数据不得丢弃）
        let dto = AspirationAttemptDTO(
            id: "x", deviceID: "dev", classCode: nil, role: "guest",
            targetWord: "跑步", triggerRate: 0.7, passed: true,
            timestamp: "2026-05-20T10:00:00Z", phase: "training",
            schemaVersion: RecordSchema.version, appVersion: "1.2 (9)"
        )
        let data = try JSONEncoder().encode(dto)
        let back = try JSONDecoder().decode(AspirationAttemptDTO.self, from: data)
        XCTAssertNil(back.classCode)
        XCTAssertTrue(back.passed)
        XCTAssertEqual(back.targetWord, "跑步")
    }

    func testFreeTextDTORoundTripPreservesArrays() throws {
        let dto = FreeTextRecordDTO(
            id: "f", deviceID: "dev", classCode: nil, role: "guest",
            originalText: "今天天气很好", tokenizedWord: "今天", pinyin: "jīn tiān",
            toneSequence: [1, 1], f0Track: [0, 120.5, 0], duration: 1.2,
            timestamp: "2026-05-20T10:00:00Z", phase: "training",
            schemaVersion: RecordSchema.version, appVersion: "1.2 (9)"
        )
        let data = try JSONEncoder().encode(dto)
        let back = try JSONDecoder().decode(FreeTextRecordDTO.self, from: data)
        XCTAssertEqual(back.toneSequence, [1, 1])
        XCTAssertEqual(back.f0Track, [0, 120.5, 0])
    }
}
