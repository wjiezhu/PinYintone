import Foundation

/// 教师端「各声调偏误分布」的数据模型。
///
/// 原文件 `GroupComparisonData.swift` 还含 A/B 两组对比的 `GroupBar` /
/// `GroupComparisonData`；取消 A/B 分组后那两个类型连同图表一并删除，
/// 这里只保留声调偏误部分。
struct ToneErrorItem: Identifiable, Codable {
    let id: UUID
    let toneType: String  // "T1" | "T2" | "T3" | "T4"
    let errorRate: Double

    init(toneType: String, errorRate: Double) {
        self.id        = UUID()
        self.toneType  = toneType
        self.errorRate = errorRate
    }

    // id 不参与编解码（后端 JSON 无此字段；解码时重新生成）
    private enum CodingKeys: CodingKey { case toneType, errorRate }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id        = UUID()
        self.toneType  = try c.decode(String.self, forKey: .toneType)
        self.errorRate = try c.decode(Double.self, forKey: .errorRate)
    }
}

struct ToneBreakdownData: Codable {
    var items: [ToneErrorItem] = []
    init() {}
}
