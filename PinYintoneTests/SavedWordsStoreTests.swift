import XCTest
@testable import PinYintone

@MainActor
final class SavedWordsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SavedWordsStore!

    override func setUp() {
        super.setUp()
        // 独立的临时 suite，避免污染真实 UserDefaults
        defaults = UserDefaults(suiteName: "pt.savedwords.tests")!
        defaults.removePersistentDomain(forName: "pt.savedwords.tests")
        store = SavedWordsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "pt.savedwords.tests")
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testAddComputesPinyinAndTones() {
        store.add("妈妈")
        XCTAssertEqual(store.words.count, 1)
        let w = store.words[0]
        XCTAssertEqual(w.word, "妈妈")
        XCTAssertEqual(w.tones, [1, 1])
        XCTAssertTrue(w.pinyin.contains("mā"))
    }

    func testAddDeduplicates() {
        store.add("北京")
        store.add("北京")
        XCTAssertEqual(store.words.count, 1, "重复词不应重复收藏")
    }

    func testNewestFirst() {
        store.add("第一")
        store.add("第二")
        XCTAssertEqual(store.words.first?.word, "第二", "新收藏应置顶")
    }

    func testToggleAndContains() {
        XCTAssertFalse(store.contains("学习"))
        store.toggle("学习")
        XCTAssertTrue(store.contains("学习"))
        store.toggle("学习")
        XCTAssertFalse(store.contains("学习"), "再次切换应取消收藏")
    }

    func testEmptyOrWhitespaceIgnored() {
        store.add("   ")
        store.add("")
        XCTAssertTrue(store.words.isEmpty)
    }

    func testPersistenceAcrossInstances() {
        store.add("朋友")
        // 新实例从同一 defaults 加载
        let reloaded = SavedWordsStore(defaults: defaults)
        XCTAssertEqual(reloaded.words.map(\.word), ["朋友"])
    }

    func testRecordPracticeKeepsBestAndCounts() {
        store.add("学习")
        store.recordPractice(word: "学习", score: 70)
        store.recordPractice(word: "学习", score: 85)
        store.recordPractice(word: "学习", score: 60)
        let w = store.words[0]
        XCTAssertEqual(w.bestScore, 85, "应保留最高分")
        XCTAssertEqual(w.practiceCount, 3, "应累计练习次数")
        XCTAssertNotNil(w.lastPracticedAt)
    }

    func testRecordPracticeNoopForUnsavedWord() {
        store.recordPractice(word: "没收藏", score: 90)
        XCTAssertTrue(store.words.isEmpty, "未收藏的词不应被记录或创建")
    }

    func testProgressPersists() {
        store.add("北京")
        store.recordPractice(word: "北京", score: 92)
        let reloaded = SavedWordsStore(defaults: defaults)
        XCTAssertEqual(reloaded.words[0].bestScore, 92)
        XCTAssertEqual(reloaded.words[0].practiceCount, 1)
    }
}
