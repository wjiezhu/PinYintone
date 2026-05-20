import Foundation

struct GroupBar: Identifiable, Codable {
    let id: UUID
    let group: String    // "A - 静态色" | "B - 动态F0"
    let avgDTW: Double
    let count: Int

    init(group: String, avgDTW: Double, count: Int) {
        self.id = UUID()
        self.group  = group
        self.avgDTW = avgDTW
        self.count  = count
    }

    // id 不参与编解码（后端 JSON 无此字段；解码时重新生成）
    private enum CodingKeys: CodingKey { case group, avgDTW, count }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id     = UUID()
        self.group  = try c.decode(String.self, forKey: .group)
        self.avgDTW = try c.decode(Double.self, forKey: .avgDTW)
        self.count  = try c.decode(Int.self,    forKey: .count)
    }
}

struct GroupComparisonData: Codable {
    var bars: [GroupBar] = []
    init() {}
}

struct ToneErrorItem: Identifiable, Codable {
    let id: UUID
    let toneType: String  // "T1" | "T2" | "T3" | "T4"
    let errorRate: Double

    init(toneType: String, errorRate: Double) {
        self.id        = UUID()
        self.toneType  = toneType
        self.errorRate = errorRate
    }

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
