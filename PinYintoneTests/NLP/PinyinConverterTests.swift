import XCTest
@testable import PinYintone

final class PinyinConverterTests: XCTestCase {
    var converter: PinyinConverter!

    override func setUp() {
        super.setUp()
        converter = PinyinConverter()
    }

    override func tearDown() {
        converter = nil
        super.tearDown()
    }

    func testPinyinWithTones() {
        // 「妈」应含 ā（阴平），「马」应含 ǎ（上声）
        XCTAssertTrue(converter.pinyin(for: "妈").contains("ā"))
        XCTAssertTrue(converter.pinyin(for: "马").contains("ǎ"))
    }

    func testPinyinWithoutTonesHasNoDiacritics() {
        let plain = converter.pinyin(for: "妈", withTones: false)
        XCTAssertEqual(plain, "ma", "去声调后应为无变音符的 ma")
    }

    func testToneSequenceMama() {
        // 妈妈 → [1, 1]
        XCTAssertEqual(converter.toneSequence(for: "妈妈"), [1, 1])
    }

    func testToneSequenceFourTones() {
        // 「妈麻马骂」覆盖一/二/三/四声
        XCTAssertEqual(converter.toneSequence(for: "妈麻马骂"), [1, 2, 3, 4])
    }

    func testToneSequenceMatchesCount() {
        // 声调序列长度应等于音节数
        let tones = converter.toneSequence(for: "中国人")
        XCTAssertEqual(tones.count, 3)
        XCTAssertTrue(tones.allSatisfy { (1...5).contains($0) })
    }
}
