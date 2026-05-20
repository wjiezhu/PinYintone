import Foundation

/// 词条类别：决定归属哪个关卡。
enum LexemeCategory: String, Codable {
    case aspiration   // 关卡 1：送气对立
    case tone         // 关卡 2：声调连读与辅音
}

struct Lexeme: Codable, Identifiable {
    let id: String              // 唯一标识，如 "paobu"
    let hanzi: String           // 汉字，如 "跑步"
    let pinyin: String          // 拼音，如 "pǎo bù"
    let tones: [Int]            // 声调序列，如 [3, 4]；轻声 = 5
    let category: LexemeCategory // 所属关卡
    let focus: String           // 考察重点，如 "P(送气)vs B(不送气)"
    let french: String          // 法语释义
    let darija: String          // 摩洛哥阿拉伯语对译
    let audioFilename: String?  // 母语者参照录音文件名（暂为 nil，用合成轮廓）
}
