import XCTest
@testable import PinYintone

final class SyncDTOTests: XCTestCase {

    func testTrainingSessionDTOEncodesExpectedKeys() throws {
        let dto = TrainingSessionDTO(
            id: "abc", deviceID: "dev", classCode: "123456", role: "student",
            groupAssignment: "dynamicF0", lexemeID: "paobu", dtwScore: 0.42,
            grade: "good", attemptNumber: 2, timestamp: "2026-05-20T10:00:00Z"
        )
        let data = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["lexemeID"] as? String, "paobu")
        XCTAssertEqual(json["groupAssignment"] as? String, "dynamicF0")
        XCTAssertEqual(json["attemptNumber"] as? Int, 2)
    }

    func testNilClassCodeEncodesAndDecodes() throws {
        // 游客（classCode = nil）应可编解码（论文：未绑定班级数据不得丢弃）
        let dto = AspirationAttemptDTO(
            id: "x", deviceID: "dev", classCode: nil, role: "guest",
            targetWord: "跑步", triggerRate: 0.7, passed: true,
            timestamp: "2026-05-20T10:00:00Z"
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
            timestamp: "2026-05-20T10:00:00Z"
        )
        let data = try JSONEncoder().encode(dto)
        let back = try JSONDecoder().decode(FreeTextRecordDTO.self, from: data)
        XCTAssertEqual(back.toneSequence, [1, 1])
        XCTAssertEqual(back.f0Track, [0, 120.5, 0])
    }
}
