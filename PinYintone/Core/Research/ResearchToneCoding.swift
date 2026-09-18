import Foundation

/// 声调编码在 App 内部与研究库之间的**唯一转换点**。
///
/// 两边约定不同，且差异是**静默**的——原样上报不会报错，数据库照单全收，
/// 只有几个月后取数的人按字典理解那一列时才会发现值对不上：
///
/// | 词 | App 内部 `Lexeme.tones` | 研究库 `citation_tones` |
/// |---|---|---|
/// | 告诉 | `[4, 5]` | `[4, 0]` |
/// | 清楚 | `[1, 5]` | `[1, 0]` |
///
/// 之所以不把 App 内部也改成 0：`5` 已嵌在 `ToneContour.hzAt(tone:)`、
/// `DirectionHint`、语料 JSON 与旧表历史数据里，改动面大且直接碰评分链路；
/// 而 `0` 在代码里读起来像「没有声调/未设置」，更容易误用。
///
/// 因此在边界转换。**研究上报不得自行拼装声调数组**，必须走本类型——
/// 服务端另有校验会拒收未转换的值，两层都拦是因为「每处都记得转换」
/// 这种约定在本项目已失效过两次。
nonisolated enum ResearchToneCoding {

    /// App 内部表示轻声的值
    static let internalNeutral = 5
    /// 研究库（字典 `citation_tones`）表示轻声的值
    static let researchNeutral = 0

    enum CodingError: Error, Equatable {
        /// 声调值不在 1–4 或轻声之内
        case unsupportedTone(Int)
        case emptySequence
    }

    /// App 内部声调序列 → 研究库 `citation_tones`。
    /// - Throws: 遇到未知调值时抛错，**不静默丢弃也不猜测**。
    static func citationTones(fromInternal tones: [Int]) throws -> [Int] {
        guard !tones.isEmpty else { throw CodingError.emptySequence }
        return try tones.map { t in
            switch t {
            case 1...4: return t
            case internalNeutral: return researchNeutral
            default: throw CodingError.unsupportedTone(t)
            }
        }
    }

    /// 研究库 → App 内部（读回历史数据时用）
    static func internalTones(fromCitation tones: [Int]) throws -> [Int] {
        guard !tones.isEmpty else { throw CodingError.emptySequence }
        return try tones.map { t in
            switch t {
            case 1...4: return t
            case researchNeutral: return internalNeutral
            default: throw CodingError.unsupportedTone(t)
            }
        }
    }
}
