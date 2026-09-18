import XCTest
@testable import PinYintone

/// 轻声编码转换。差异是静默的——原样上报不报错，只有取数时才发现值对不上，
/// 而语料 20 词里有 3 个含轻声。
final class ResearchToneCodingTests: XCTestCase {

    func testNeutralToneIsRemapped() throws {
        // 告诉 [4,5] → [4,0]；清楚 [1,5] → [1,0]
        XCTAssertEqual(try ResearchToneCoding.citationTones(fromInternal: [4, 5]), [4, 0])
        XCTAssertEqual(try ResearchToneCoding.citationTones(fromInternal: [1, 5]), [1, 0])
    }

    func testNonNeutralTonesUnchanged() throws {
        for t in 1...4 {
            XCTAssertEqual(try ResearchToneCoding.citationTones(fromInternal: [t]), [t])
        }
        XCTAssertEqual(try ResearchToneCoding.citationTones(fromInternal: [3, 4]), [3, 4])
    }

    func testRoundTrip() throws {
        let original = [1, 5, 4, 3, 2]
        let research = try ResearchToneCoding.citationTones(fromInternal: original)
        XCTAssertEqual(research, [1, 0, 4, 3, 2])
        XCTAssertEqual(try ResearchToneCoding.internalTones(fromCitation: research), original)
    }

    func testUnknownToneThrowsRatherThanGuessing() {
        // 不静默丢弃、不猜测——宁可上报失败也不写错数据
        XCTAssertThrowsError(try ResearchToneCoding.citationTones(fromInternal: [1, 9])) {
            XCTAssertEqual($0 as? ResearchToneCoding.CodingError, .unsupportedTone(9))
        }
        // 0 在 App 内部不是合法调值（那是研究库的轻声码）
        XCTAssertThrowsError(try ResearchToneCoding.citationTones(fromInternal: [0]))
        XCTAssertThrowsError(try ResearchToneCoding.citationTones(fromInternal: []))
    }

    func testResearchSideRejectsInternalNeutralCode() {
        // 5 在研究库侧不是合法值，读回时必须报错
        XCTAssertThrowsError(try ResearchToneCoding.internalTones(fromCitation: [1, 5]))
    }

    /// 真实语料全量过一遍：每个词都能无损转换
    func testWholeCorpusConvertsCleanly() throws {
        let lexemes = CorpusLoader.shared.loadLexemes()
        XCTAssertFalse(lexemes.isEmpty)
        var neutralCount = 0
        for lex in lexemes {
            let cited = try ResearchToneCoding.citationTones(fromInternal: lex.tones)
            XCTAssertEqual(cited.count, lex.tones.count)
            XCTAssertFalse(cited.contains(5), "\(lex.hanzi) 转换后仍含 5")
            if lex.tones.contains(5) { neutralCount += 1 }
            XCTAssertEqual(try ResearchToneCoding.internalTones(fromCitation: cited), lex.tones)
        }
        XCTAssertGreaterThan(neutralCount, 0, "语料应含轻声词，否则本测试没覆盖到关键路径")
    }
}
