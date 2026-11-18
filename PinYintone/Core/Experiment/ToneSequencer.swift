import Combine
import Foundation

/// 声调普通练习的选词与顺序（需求 R06）。
///
/// 没有阶段，没有门槛：全部声调词条都可以直接练。「下一个」**随机给出**
/// （一轮之内每个词出现一次，见 `ShuffledOrder`），也可以从词表里挑任意一个。不需要先完成前测、练遍词库或达到某个分数。
///
/// 历史说明：本类型曾是「前测 → 训练 → 后测」三阶段的状态机，
/// 前测走完才进训练、训练池练遍才解锁后测。那套流程与「自主选择练习内容、
/// 时间和次数」直接矛盾，已整体移除。升级前存下的阶段与游标
/// （`pt_tone_phase`、`pt_tone_cursor_*`）**不再读取**——
/// 已安装用户升级后直接进普通练习，不会被旧的前测游标挡住。
@MainActor
final class ToneSequencer: ObservableObject {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = ToneSequencer()

    /// 当前词在词表中的位置（1-based）与总数
    @Published private(set) var progress: (index: Int, total: Int) = (0, 0)
    @Published private(set) var currentLexeme: Lexeme?

    /// 当前词在 `pool` 里的下标
    private var cursor: Int = 0
    /// 这一轮乱序的种子
    private var seed: Int
    private let seedSource: () -> Int
    private static let cursorKey = "pt_tone_practice_cursor"
    private static let seedKey = "pt_tone_practice_seed"

    /// - Parameter seedSource: 取新一轮的种子。测试里传固定值
    init(seedSource: (() -> Int)? = nil) {
        let source = seedSource ?? ShuffledOrder.newSeed
        self.seedSource = source
        let defaults = UserDefaults.standard
        cursor = defaults.integer(forKey: Self.cursorKey)
        if let saved = defaults.object(forKey: Self.seedKey) as? Int {
            seed = saved
        } else {
            seed = source()
            defaults.set(seed, forKey: Self.seedKey)
            // 第一次进练习：从这一轮的第一个词开始，不是人人都从同一个词开始。
            // 升级上来、已经停在某个词上的人留在原来的词
            if defaults.object(forKey: Self.cursorKey) == nil,
               let first = ShuffledOrder.permutation(
                   count: CorpusLoader.shared.orderedPool(category: .tone).count, seed: seed).first {
                cursor = first
                defaults.set(cursor, forKey: Self.cursorKey)
            }
        }
        refresh()
    }

    /// 这一轮的出词顺序（`pool` 的下标）
    private var order: [Int] { ShuffledOrder.permutation(count: pool.count, seed: seed) }

    /// 普通练习的词表：全部声调词条。这是**选词列表里的排列顺序**，不是出词顺序。
    /// 原「测试词集」的词也在其中——自愿练习不要求练习词与自测词不重叠，
    /// 自测时如实记录该词此前练过几次。
    var pool: [Lexeme] { CorpusLoader.shared.orderedPool(category: .tone) }

    /// 下一个词：随机顺序里的下一个。一轮走完换一轮新的顺序，没有「完成」死路
    func advance() {
        let order = self.order
        guard !order.isEmpty else { return }
        let position = order.firstIndex(of: cursor) ?? -1
        if position + 1 < order.count {
            cursor = order[position + 1]
        } else {
            let last = cursor
            seed = seedSource()
            UserDefaults.standard.set(seed, forKey: Self.seedKey)
            let next = self.order
            // 新一轮的头一个词不与刚练完的那个相同
            cursor = (next[0] == last && next.count > 1) ? next[1] : next[0]
        }
        persist()
    }

    /// 直接选某个词。词表里没有就不动。
    @discardableResult
    func select(lexemeID: String) -> Bool {
        guard let i = pool.firstIndex(where: { $0.id == lexemeID }) else { return false }
        cursor = i
        persist()
        return true
    }

    private func persist() {
        UserDefaults.standard.set(cursor, forKey: Self.cursorKey)
        refresh()
    }

    private func refresh() {
        let pool = self.pool
        guard !pool.isEmpty else {
            currentLexeme = nil
            progress = (0, 0)
            return
        }
        cursor = ((cursor % pool.count) + pool.count) % pool.count
        currentLexeme = pool[cursor]
        // 进度是这一轮里的第几个，不是词表里的第几个
        progress = ((order.firstIndex(of: cursor) ?? 0) + 1, pool.count)
    }

    /// 删除账号时清掉练习位置
    static let storageKeys = [cursorKey, seedKey]
}

/// 一次可选自测的进度（需求 R06 / U04）。
///
/// 只存在于内存：自测是学习者主动开始、可随时取消的一小段，
/// 取消或完成都回到普通练习，不留下「做到一半」的状态，也不会锁住什么。
nonisolated struct SelfTestSession: Equatable {
    let words: [Lexeme.ID]
    private(set) var index = 0

    init(words: [Lexeme.ID]) { self.words = words }

    var total: Int { words.count }
    /// 1-based，用于显示「第 x / n 词」
    var position: Int { min(index + 1, max(total, 1)) }
    var currentID: Lexeme.ID? { index < words.count ? words[index] : nil }
    var isFinished: Bool { index >= words.count }

    /// 当前词有效录完，进入下一词。技术失败不调用——没录上不算完成这一题。
    mutating func completeCurrent() {
        if index < words.count { index += 1 }
    }
}
