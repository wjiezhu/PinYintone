import Foundation

/// 用户收藏的练习词条（本地持久化，个人便利清单，不参与云端同步）。
struct SavedWord: Codable, Identifiable, Equatable {
    let id: UUID
    let word: String
    let pinyin: String
    let tones: [Int]
    let savedAt: Date
}
