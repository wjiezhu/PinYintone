import Foundation

struct Lexeme: Codable, Identifiable {
    let id: String           // 唯一标识，如 "ma1_shang4"
    let hanzi: String        // 汉字，如 "马上"
    let pinyin: String       // 拼音，如 "mǎ shàng"
    let tones: [Int]         // 声调序列，如 [3, 4]
    let audioFilename: String? // 母语者参照录音文件名
}
