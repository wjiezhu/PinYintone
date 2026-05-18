import Foundation

enum FeedbackGrade: String, Codable {
    case excellent      // DTW ≤ 0.2
    case good           // DTW 0.2–0.35
    case needsPractice  // DTW 0.35–0.5
    case fail           // DTW > 0.5
}

struct FeedbackResult {
    let dtwScore: Float
    let grade: FeedbackGrade
    let attemptNumber: Int
    let toneErrors: [Int]  // 发音错误的音节下标
}
