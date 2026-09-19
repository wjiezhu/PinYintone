import XCTest
@testable import PinYintone

/// App ↔ 服务端的时间契约。
///
/// 历史缺陷：研究接口用了默认 JSONEncoder，日期被编码成自 2001 年起的秒数，
/// 服务端按 1970 解读，**差 31 年**——2026-09-19 被存成 1995-09-19，返回 200、
/// 导出为空、全程无报错。268 个单元测试当时全部通过，因为两端从没测过彼此的格式。
final class ResearchJSONTests: XCTestCase {

    private struct D: Codable { let at: Date }
    private let known = ISO8601DateFormatter().date(from: "2026-09-19T08:30:00Z")!

    /// 编码出的必须是 ISO8601 **字符串**，不能是数字
    func testEncodesAsIsoStringNotNumber() throws {
        let json = String(data: try ResearchJSON.encoder.encode(D(at: known)), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"2026-09-19T08:30:00"), "应为 ISO 字符串，实得 \(json)")
        XCTAssertTrue(json.contains("Z\""), "必须带时区")
        XCTAssertFalse(json.contains("811"), "不得出现 2001 基准的秒数")
    }

    /// 反例固化：默认编码器确实会产出数字——这正是事故的成因
    func testDefaultEncoderWouldHaveProducedNumber() throws {
        let data = try JSONEncoder().encode(D(at: known))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertTrue(obj?["at"] is NSNumber,
                      "默认编码器产出数字（2001 基准秒数）——这正是事故成因。" +
                      "若此断言失败，说明系统默认行为变了，需重新评估")
        // 且这个数字按 1970 解读会落在 1990 年代
        let n = (obj?["at"] as? NSNumber)?.doubleValue ?? 0
        let misread = Date(timeIntervalSince1970: n)
        XCTAssertLessThan(Calendar(identifier: .gregorian).component(.year, from: misread), 2000,
                          "按 Unix 纪元误读会差约 31 年")
    }

    /// Python isoformat() 在微秒为零时不输出小数，非零时输出——两种都要能解
    func testDecodesBothPythonIsoformatVariants() throws {
        for s in ["2026-09-19T08:30:00+00:00", "2026-09-19T08:30:00.123456+00:00",
                  "2026-09-19T08:30:00Z", "2026-09-19T08:30:00.000Z"] {
            let d = try ResearchJSON.decoder.decode(D.self, from: "{\"at\":\"\(s)\"}".data(using: .utf8)!)
            XCTAssertEqual(d.at.timeIntervalSince(known), 0, accuracy: 1, "解码 \(s) 出错")
        }
    }

    /// 不带时区的串**拒绝**，不按本地时区猜——猜错会让采集窗口边界漂移
    func testRejectsTimezoneLessString() {
        XCTAssertThrowsError(try ResearchJSON.decoder.decode(
            D.self, from: #"{"at":"2026-09-19T08:30:00"}"#.data(using: .utf8)!))
    }

    func testRoundTrip() throws {
        let data = try ResearchJSON.encoder.encode(D(at: known))
        XCTAssertEqual(try ResearchJSON.decoder.decode(D.self, from: data).at
                        .timeIntervalSince(known), 0, accuracy: 0.001)
    }
}
