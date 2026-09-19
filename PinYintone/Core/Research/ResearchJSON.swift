import Foundation

/// 研究接口专用的 JSON 编解码：日期一律 ISO8601 字符串（带时区、含小数秒）。
///
/// ⚠ 为什么不能用默认的 `JSONEncoder()` / `JSONDecoder()`：
/// 默认策略 `.deferredToDate` 把日期编码成**自 2001-01-01 起的秒数**（Apple 参考时间），
/// 而服务端 pydantic 把数字当**自 1970-01-01 起的秒数**（Unix 时间）解读——
/// 差整整 31 年。实测：App 发出 2026-09-19，服务端返回 200 并存成 **1995-09-19**。
/// 后果是所有研究记录落在采集窗口之外，**导出结果为空，且全程无任何报错**。
/// 反方向同样坏：服务端下发的 ISO 字符串用默认解码器解不出来，
/// `ResearchConfig.refresh()` 静默失败，研究邀请永远不出现。
///
/// 为什么不全局改：教师看板等旧接口**依赖** `.deferredToDate`
/// （服务端 `_apple_ts` 专门返回 2001 基准的秒数），全局改会把它们打坏。
/// 旧同步链路则是把日期预先格式化成字符串字段绕开的。
nonisolated enum ResearchJSON {

    /// 带小数秒的 ISO8601。Python `datetime.isoformat()` 在微秒非零时会输出小数部分，
    /// 为零时不输出——两种都要能解。
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // 带小数秒：同一秒内的多个事件需要保持先后顺序
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(withFraction.string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = withFraction.date(from: s) ?? plain.date(from: s) {
                return date
            }
            // 不带时区的串**拒绝解码**而不是按本地时区猜：猜错会让窗口边界漂移数小时
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "研究接口要求带时区的 ISO8601 时间，收到：\(s)")
        }
        return d
    }()
}
