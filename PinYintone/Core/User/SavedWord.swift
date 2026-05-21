import Foundation

/// 用户收藏的练习词条（本地持久化，个人便利清单，不参与云端同步）。
struct SavedWord: Codable, Identifiable, Equatable {
    let id: UUID
    let word: String
    let pinyin: String
    let tones: [Int]
    let savedAt: Date
    var bestScore: Int?            // 历史最佳百分制得分
    var practiceCount: Int         // 练习次数
    var lastPracticedAt: Date?     // 最近练习时间

    init(id: UUID, word: String, pinyin: String, tones: [Int], savedAt: Date,
         bestScore: Int? = nil, practiceCount: Int = 0, lastPracticedAt: Date? = nil) {
        self.id = id
        self.word = word
        self.pinyin = pinyin
        self.tones = tones
        self.savedAt = savedAt
        self.bestScore = bestScore
        self.practiceCount = practiceCount
        self.lastPracticedAt = lastPracticedAt
    }

    // 向后兼容：旧存储数据缺少进度字段时给默认值
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        word = try c.decode(String.self, forKey: .word)
        pinyin = try c.decode(String.self, forKey: .pinyin)
        tones = try c.decode([Int].self, forKey: .tones)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        bestScore = try c.decodeIfPresent(Int.self, forKey: .bestScore)
        practiceCount = try c.decodeIfPresent(Int.self, forKey: .practiceCount) ?? 0
        lastPracticedAt = try c.decodeIfPresent(Date.self, forKey: .lastPracticedAt)
    }
}
