import Foundation

struct GroupBar: Identifiable {
    let id = UUID()
    let group: String    // "A - 静态色" | "B - 动态F0"
    let avgDTW: Double
    let count: Int
}

struct GroupComparisonData {
    var bars: [GroupBar] = []
    init() {}
}

struct ToneErrorItem: Identifiable {
    let id = UUID()
    let toneType: String  // "T1" | "T2" | "T3" | "T4"
    let errorRate: Double
}

struct ToneBreakdownData {
    var items: [ToneErrorItem] = []
    init() {}
}
