import Foundation

/// 随机出词用的乱序（研究者 2026-11-19 要求：练习的词随机给出）。
///
/// 由一个种子决定一整轮的顺序：同一个种子总是得到同一个排列，所以一轮之内
/// **每个词出现一次、不重复**，杀掉 App 再进来也接着同一轮往下走；一轮走完换新种子。
/// 种子是每台设备各自随机取的，不按人、不按词集分配，**不是实验条件**。
nonisolated enum ShuffledOrder {

    /// SplitMix64：只为了「同一个种子得到同一个排列」，不用于任何安全用途
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// 0..<count 的一个排列
    static func permutation(count: Int, seed: Int) -> [Int] {
        guard count > 0 else { return [] }
        var generator = Generator(state: UInt64(bitPattern: Int64(seed)))
        return Array(0..<count).shuffled(using: &generator)
    }

    static func newSeed() -> Int { Int.random(in: 1...Int(Int32.max)) }
}
