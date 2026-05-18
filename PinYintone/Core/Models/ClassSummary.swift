import Foundation

struct ClassSummary: Codable {
    let totalStudents: Int
    let weeklyNewStudents: Int?
    let avgDTW: Double
    let passRate: Double  // 0.0 – 1.0
}
