import Foundation

/// 现场实测协议（2026-10-28 起）：前测 → 训练 → 后测。
///
/// 研究者在场，学习者用自己的手机一口气做完：
/// - **前测**：测试词各录一次，**不显示任何结果**（与自测同样的裸测）。
/// - **训练**：训练词逐个练，有反馈；每个词得到规定次数的有效结果才换下一个。
/// - **后测**：同一组测试词再录一次，同样不显示结果。
///
/// 测试词与训练词**不重叠**：后测的变化不能来自「刚练过这个词」。
///
/// 与服务端读的是**同一份** `field_protocol.json`。配置里绑定的协议必须与本机携带的一致
/// （版本号与每个词的版本编号），对不上就不提供现场实测——不能带着别的词表去测，
/// 测出来的成绩没法与别人比较。
nonisolated struct FieldProtocol: Decodable, Equatable {
    let protocolVersion: String
    let testWords: [Lexeme.ID]
    let trainingWords: [Lexeme.ID]
    let trainingValidAttemptsPerWord: Int

    static let bundled: FieldProtocol? = {
        guard let url = Bundle.main.url(forResource: "field_protocol", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FieldProtocol.self, from: data)
    }()

    /// 配置下发的协议是否就是本机携带的这份
    func matches(_ spec: APIClient.FieldProtocolSpec, version: String?) -> Bool {
        guard version == protocolVersion,
              spec.lexiconVersion == ResearchLexicon.lexiconVersion,
              spec.trainingValidAttemptsPerWord == trainingValidAttemptsPerWord else { return false }
        let test = testWords.map { ResearchLexicon.versionID(for: $0) }
        let train = trainingWords.map { ResearchLexicon.versionID(for: $0) }
        return test == spec.testLexemeVersionIDs.map(Optional.some)
            && train == spec.trainingLexemeVersionIDs.map(Optional.some)
    }
}

/// 一次现场实测走到了哪一步。只在内存里：中途离开就是结束，不留「做到一半」的状态。
/// 下次再做是一次新的实测（新的流程编号），前测从头开始。
nonisolated struct FieldSession: Equatable {

    enum Step: String, Equatable, CaseIterable {
        case pretest, training, posttest

        var next: Step? {
            switch self {
            case .pretest: return .training
            case .training: return .posttest
            case .posttest: return nil
            }
        }
    }

    let id: UUID
    let protocolVersion: String
    let testWords: [Lexeme.ID]
    let trainingWords: [Lexeme.ID]
    let validAttemptsPerWord: Int

    /// 说明页之后才算开始（点了「开始」才进前测）
    private(set) var started = false
    private(set) var step: Step = .pretest
    /// 当前这一段里第几个词（0-based）
    private(set) var index = 0
    /// 训练段：当前词已得到几次有效结果
    private(set) var validCount = 0
    /// 当前这一段已走完，等学习者点「继续」进入下一段
    private(set) var stepFinished = false
    /// 三段全部走完
    private(set) var isComplete = false

    init(protocol p: FieldProtocol, id: UUID = UUID()) {
        self.id = id
        protocolVersion = p.protocolVersion
        testWords = p.testWords
        trainingWords = p.trainingWords
        validAttemptsPerWord = max(1, p.trainingValidAttemptsPerWord)
    }

    var words: [Lexeme.ID] { step == .training ? trainingWords : testWords }
    var currentID: Lexeme.ID? {
        guard started, !stepFinished, !isComplete, index < words.count else { return nil }
        return words[index]
    }
    /// 1-based，用于「第 x / n 词」
    var position: Int { min(index + 1, max(words.count, 1)) }
    var total: Int { words.count }
    var isBareTest: Bool { step != .training }

    /// 前测 / 后测：当前词有效录完，进下一个。技术失败不调用——没录上不算完成这一题。
    mutating func completeTestWord() {
        guard isBareTest, !stepFinished else { return }
        advanceWord()
    }

    /// 训练：当前词得到一次有效结果。返回这个词是否已练够。
    @discardableResult
    mutating func recordTrainingResult() -> Bool {
        guard step == .training, !stepFinished else { return false }
        validCount += 1
        return validCount >= validAttemptsPerWord
    }

    /// 训练：练够了，换下一个词
    mutating func nextTrainingWord() {
        guard step == .training, validCount >= validAttemptsPerWord else { return }
        advanceWord()
    }

    /// 说明页点了「开始」
    mutating func start() { started = true }

    /// 学习者在段落之间点了「继续」
    mutating func beginNextStep() {
        guard stepFinished, let next = step.next else { return }
        step = next
        index = 0
        validCount = 0
        stepFinished = false
    }

    private mutating func advanceWord() {
        index += 1
        validCount = 0
        if index >= words.count {
            stepFinished = true
            if step.next == nil { isComplete = true }
        }
    }
}
