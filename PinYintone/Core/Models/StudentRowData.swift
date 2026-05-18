import Foundation

struct StudentRowData: Codable, Identifiable {
    let id: String           // deviceID
    let nickname: String?
    let totalSessions: Int
    let recentPassRate: Double
    let lastActiveAt: Date?
}

struct StudentDetailData: Codable {
    let deviceID: String
    let dtwTimeSeries: [Double]  // 按训练时间排序的 DTW 分数
    let errorWords: [String]     // 偏误频率最高的词
}
