import XCTest
@testable import PinYintone

/// 随包资源的兜底检查。
///
/// 背景：资源文件放进 `Resources/` 目录**不等于**进了 App bundle，而且这类问题
/// 是静默的——编译不报错，单元测试若查的是测试自己的 bundle 也会一片绿，
/// 只有真机运行时读不到。本问卷定义初版就踩过：三份 JSON 全部加载失败。
///
/// 因此这里不逐个点名文件，而是**扫描整个 App bundle**：任何随包 JSON
/// 都必须能被解析。以后新增资源自动纳入保护，不依赖谁记得补测试。
final class BundledResourceTests: XCTestCase {

    /// App bundle 里的全部 JSON 都必须是合法且可解析的
    func testAllBundledJSONParses() throws {
        let bundle = Bundle.main
        guard let root = bundle.resourceURL else {
            return XCTFail("取不到 App bundle 的 resourceURL")
        }
        let urls = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        XCTAssertFalse(urls.isEmpty, "App bundle 里一个 JSON 都没有，说明资源没被收录")

        for url in urls {
            let data = try Data(contentsOf: url)
            XCTAssertFalse(data.isEmpty, "\(url.lastPathComponent) 是空文件")
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data),
                             "\(url.lastPathComponent) 不是合法 JSON")
        }
    }

    /// 关键资源必须在位——这几份缺了功能直接不可用，值得单独点名
    func testCriticalResourcesPresent() {
        let required = ["lexemes"] + SurveyFormLoader.formKeys + ["survey_ui_v1"]
        for name in required {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "json"),
                            "\(name).json 未随包发布")
        }
    }
}
