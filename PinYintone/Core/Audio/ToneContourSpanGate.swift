import Foundation

/// 非一声词的走势幅度闸门：DTW 判不出「读平」，这里补一刀。
///
/// 为什么需要它：DTW 比的是 z-score 归一化后的**形状**，归一化是尺度不变的——
/// 1 个半音的漂移和 10 个半音的四声被拉成同样大小的曲线，形状对上就通关。
/// 实测非一声词读平约 2/3 通关，走势压到正常的 10%（约 0.9 半音）仍 93–99% 通关
/// （见 `docs/SCORING_FLAT_READING_STUDY.md`）。改 DTW 分母或加带宽都解决不了，
/// 只能在**保留幅度**的标度上判：相对的半音。
///
/// 与 `ToneDirectionGate` 方向相反：那道门拦「该平却往下掉」（只管全一声的词），
/// 这道门拦「该有起伏却几乎没动」（只管含二 / 三 / 四声的词），**从不因为有起伏而判错**。
/// 两道门的适用范围不重叠；1+5（一声 + 轻声）两道都不管。
enum ToneContourSpanGate {

    /// 走势跨度下限（半音）。低于此值 = 读平，不通关。
    ///
    /// 标定（合成集 + macOS TTS 音频）：读平的跨度 P99 约 1.6 半音；
    /// 正确读法跨度最小的 2+2、3+1 的 P1 约 2.5–2.8 半音。取 2.0 只拦「基本没动」的，
    /// 「动得不够」交给 DTW。真实学习者数据到位后再校准（记录里带了 `pitchSpanSemitones`）。
    static let minSpanSemitones: Float = 2.0

    /// 计算跨度所需的最少有声帧
    static let minVoicedFrames = 6

    /// 该词是否适用：至少有一个二 / 三 / 四声
    static func applies(tones: [Int]) -> Bool {
        tones.contains { (2...4).contains($0) }
    }

    /// 走势跨度（半音）：有声帧排序后，P90 与 P10 的音程。
    /// 分位取下标 `Int((count − 1) × p)`，不插值。
    /// **必须传原始 Hz 轨迹**（clean 之后、归一化之前）——归一化后幅度已丢失。
    /// 有声帧少于 `minVoicedFrames` 时返回 nil。与词的声调无关，任何词都可计算。
    ///
    /// 用 Double 计算再转 Float：两端（Swift / Kotlin）的 Float 对数实现不同，
    /// Double 算完再舍入到 Float 才能两端一致。
    static func spanSemitones(hzTrack: [Float]) -> Float? {
        let voiced = hzTrack.filter { $0 > 0 }.sorted()
        guard voiced.count >= minVoicedFrames else { return nil }
        let last = Double(voiced.count - 1)
        let p10 = Double(voiced[Int(last * 0.1)])
        let p90 = Double(voiced[Int(last * 0.9)])
        return Float(12 * log2(p90 / p10))
    }

    /// 是否判定为「读平」：适用的词、跨度可算、且小于下限。
    static func fails(hzTrack: [Float], tones: [Int]) -> Bool {
        guard applies(tones: tones), let span = spanSemitones(hzTrack: hzTrack) else { return false }
        return span < minSpanSemitones
    }
}
