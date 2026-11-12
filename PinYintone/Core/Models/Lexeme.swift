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
    /// 关卡 2 词集归属（升级需求 §3.2）。反馈条件绑定在词集上，不绑定学习者。
    /// 关卡 1（送气）词条无此字段，解码为 nil。
    let wordSet: WordSet?
    /// 关卡 1（送气）考察的声母，都在词的第一个字上。声调词条为 nil。
    var aspirationTarget: AspirationTarget? = nil
    /// 西班牙语、意大利语释义（界面选这两种语言时显示）
    var spanish: String? = nil
    var italian: String? = nil
}

/// 这个词考察的声母，以及它是不是送气音。写在语料里，不从 `focus` 的说明文字里猜。
struct AspirationTarget: Codable, Equatable {
    let initial: String         // p / t / k（送气）或 b / d / g（不送气）
    let aspirated: Bool
}
