import Foundation

/// 平调词的走向闸门：DTW 判不出「掉调」，这里补一刀。
///
/// 为什么需要它：DTW 比的是 z-score 归一化后的**形状**，而归一化是尺度不变的——
/// 学习者降 45 Hz 和降 80 Hz 归一化后是同一条斜坡，距离会饱和在 0.5 通关线以下，
/// 于是全一声的词读成一路下滑也照样通关。实测参照与候选的距离上限约 0.49，
/// 无论把理想轮廓调得多平都翻不过去（见 `docs/LEVEL_TONE_SCORING.md`）。
///
/// 所以这一刀必须在**保留音程幅度**的标度上下：相对自身中位数的半音。
/// 半音是对数比，天然与音域无关，男声童声同一形状得数相同。
///
/// 只管**全部音节都是一声**的词：其余声调本就该有起伏，DTW 处理得很好
/// （4+4 实测正确 0.081 / 错误平读 0.933，方向完全正常），不必也不该插手。
enum ToneDirectionGate {

    /// 全平调词允许的最大首末下滑（半音，四分之一八度）。
    ///
    /// 标定：理想 T1 轮廓自身为 -0.27 半音（必须放行，余量极大）；
    /// 自然句调下倾通常在 2 半音以内；实测词降 60 Hz ≈ -3.11、80 Hz ≈ -4.30 半音。
    /// 取 3.0 只拦明显读错的，不替 DTW 做边界判断。
    static let maxFallSemitones: Float = 3.0

    /// 该词是否全部为一声（闸门只对这类词生效）
    static func applies(tones: [Int]) -> Bool {
        !tones.isEmpty && tones.allSatisfy { $0 == 1 }
    }

    /// 首末三分之一的落差（半音，负 = 下滑）。
    /// **必须传原始 Hz 轨迹**——归一化后幅度已丢失，算出来没有意义。
    /// 词不适用或有声帧太少时返回 nil。
    static func fallSemitones(hzTrack: [Float], tones: [Int]) -> Float? {
        guard applies(tones: tones) else { return nil }
        let voiced = hzTrack.filter { $0 > 0 }
        guard voiced.count >= 6 else { return nil }

        let third = max(1, voiced.count / 3)
        let head = voiced.prefix(third).reduce(0, +) / Float(third)
        let tail = voiced.suffix(third).reduce(0, +) / Float(third)
        guard head > 0, tail > 0 else { return nil }
        return 12 * log2(tail / head)
    }

    /// 是否判定为「掉调」——全平调词下滑超过阈值。
    static func fails(hzTrack: [Float], tones: [Int]) -> Bool {
        guard let fall = fallSemitones(hzTrack: hzTrack, tones: tones) else { return false }
        return fall < -maxFallSemitones
    }
}
