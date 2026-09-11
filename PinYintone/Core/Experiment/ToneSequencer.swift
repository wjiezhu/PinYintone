import Combine
import Foundation

/// 关卡 2 的出题与阶段推进（升级需求 §3.1 / §3.2）。
///
/// 三阶段共用同一算法与阈值，差别只在词集与反馈呈现：
/// - `pretest` / `posttest`：遍历固定测试词集一次，每词一遍，走完即阶段完成。
/// - `training`：循环遍历训练池（全部非测试词条），反馈一律为动态 F0 可视化。
///
/// 阶段流转：
/// - 前测走完 → 自动进入训练；
/// - 训练词集全部练过至少一次 → 解锁后测（由学习者/研究者主动开始，不自动跳）；
/// - 后测走完 → 停在完成态，不回退。
@MainActor
final class ToneSequencer: ObservableObject {
    static let shared = ToneSequencer()

    @Published private(set) var phase: TrainingPhase
    /// 测试阶段是否已走完全部词条
    @Published private(set) var isPhaseComplete: Bool = false
    /// 当前题目在本阶段词表中的位置（1-based）与总数
    @Published private(set) var progress: (index: Int, total: Int) = (0, 0)

    private var cursor: Int = 0

    private static let phaseKey = "pt_tone_phase"
    private static func cursorKey(_ phase: TrainingPhase) -> String {
        "pt_tone_cursor_\(phase.rawValue)"
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.phaseKey)
        phase = raw.flatMap(TrainingPhase.init(rawValue:)) ?? .pretest
        cursor = UserDefaults.standard.integer(forKey: Self.cursorKey(phase))
        refreshDerivedState()
    }

    // MARK: - 词表

    /// 当前阶段的词表。测试阶段为固定测试词集；训练阶段为合并后的训练池。
    var pool: [Lexeme] {
        switch phase {
        case .pretest, .posttest:
            return CorpusLoader.shared.assessmentPool()
        case .training:
            // 训练池 = 全部非测试词条（原 set1 + set2 合并，不再分块）
            return WordSet.trainingSets.flatMap {
                CorpusLoader.shared.tonePool(wordSet: $0)
            }
        }
    }

    /// 当前题目。测试阶段走完后返回 nil（进入阶段完成态）。
    var currentLexeme: Lexeme? {
        let pool = self.pool
        guard !pool.isEmpty else { return nil }
        if phase.isAssessment {
            return cursor < pool.count ? pool[cursor] : nil
        }
        return pool[cursor % pool.count]
    }

    // MARK: - 推进

    /// 进入下一题。测试阶段走到末尾即标记阶段完成；前测完成自动转入训练。
    func advance() {
        let pool = self.pool
        guard !pool.isEmpty else { return }
        if phase.isAssessment {
            cursor += 1
            persistCursor()
            if cursor >= pool.count {
                if phase == .pretest {
                    // 前测做完直接进训练，避免学习者停在"不知道下一步"的空页
                    enter(.training)
                    return
                }
                isPhaseComplete = true
            }
        } else {
            cursor = (cursor + 1) % pool.count
            persistCursor()
        }
        refreshDerivedState()
    }

    /// 后测解锁条件：训练池里每个词都至少练过一次
    var isPosttestUnlocked: Bool {
        let ids = WordSet.trainingSets
            .flatMap { CorpusLoader.shared.tonePool(wordSet: $0) }
            .map(\.id)
        return ToneAttemptStore.allAttempted(ids)
    }

    /// 主动开始后测（训练阶段解锁后由学习者/研究者触发）
    func beginPosttest() {
        guard isPosttestUnlocked else { return }
        enter(.posttest, resetCursor: true)
    }

    /// 重做当前阶段（仅调试 / 重新开始实验用）
    func restartPhase() {
        cursor = 0
        persistCursor()
        refreshDerivedState()
    }

    // MARK: - 私有

    private func enter(_ next: TrainingPhase, resetCursor: Bool = true) {
        phase = next
        UserDefaults.standard.set(next.rawValue, forKey: Self.phaseKey)
        cursor = resetCursor ? 0 : UserDefaults.standard.integer(forKey: Self.cursorKey(next))
        persistCursor()
        refreshDerivedState()
    }

    private func persistCursor() {
        UserDefaults.standard.set(cursor, forKey: Self.cursorKey(phase))
    }

    private func refreshDerivedState() {
        let total = pool.count
        if phase.isAssessment {
            isPhaseComplete = total > 0 && cursor >= total
            progress = (min(cursor + 1, max(total, 1)), total)
        } else {
            isPhaseComplete = false
            progress = (total > 0 ? (cursor % total) + 1 : 0, total)
        }
    }
}
