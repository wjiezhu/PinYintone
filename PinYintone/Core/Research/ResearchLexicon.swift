import Foundation

/// 研究词表：`lexeme_id`（稳定）→ `lexeme_version_id`（版本级）的映射。
///
/// 与后端种子脚本读**同一份** `research_lexicon.json`，是两端共同的唯一真源。
///
/// ⚠ 历史缺陷：此前上报时直接把 `Lexeme.id`（如 "paobu"）当成
/// `lexemeVersionID`。但 `research_lexemes` 的主键是**版本级**编号——
/// 词条内容或示范一改就换新编号（字典 §6）。稳定编号永远对不上任何一行，
/// 尝试记录与事件的词条外键全部悬空。**上报研究数据时一律经本类型转换。**
nonisolated enum ResearchLexicon {

    struct Entry: Decodable {
        let lexemeID: String
        let lexemeVersionID: String
        let reviewStatus: String
        let teacherHintText: String?
        let teacherHintVersion: String?
    }

    struct File: Decodable {
        let lexiconVersion: String
        let entries: [Entry]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "research_lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    private static let byLexemeID: [String: Entry] = {
        Dictionary(uniqueKeysWithValues: (file?.entries ?? []).map { ($0.lexemeID, $0) })
    }()

    static var lexiconVersion: String? { file?.lexiconVersion }

    /// 取版本级编号。词表里没有该词时返回 nil——**不回退成稳定编号**，
    /// 那样只会重新制造悬空外键。
    static func versionID(for lexemeID: String?) -> String? {
        guard let lexemeID else { return nil }
        return byLexemeID[lexemeID]?.lexemeVersionID
    }

    /// 该词**经教师核对**的目标词提示。未核对或没有提示时返回 nil——
    /// 字典 §9：「词条无已核对提示时不得套用别词提示」。
    static func approvedHint(for lexemeID: String) -> (text: String, version: String)? {
        guard let e = byLexemeID[lexemeID], e.reviewStatus == "approved",
              let text = e.teacherHintText, !text.isEmpty,
              let version = e.teacherHintVersion else { return nil }
        return (text, version)
    }

    /// 是否已通过教师核对。未核对的词条不得用于正式采集（字典 §6）。
    static func isApproved(_ lexemeID: String) -> Bool {
        byLexemeID[lexemeID]?.reviewStatus == "approved"
    }
}
