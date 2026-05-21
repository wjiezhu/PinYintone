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
}
