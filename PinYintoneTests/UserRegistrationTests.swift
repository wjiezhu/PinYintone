import XCTest
@testable import PinYintone

/// 登录不等后端建档。
///
/// 服务器慢或连不上时，建档请求要等到 60 秒超时。此前登录要等它返回才进首页，
/// 真机 TestFlight 上表现为「登录一直在转」。这里用一直不回的假服务器复现。
@MainActor
final class UserRegistrationTests: XCTestCase {

    private let profileKey = "pt_user_profile"
    private let registeredKey = "pt_registered_profile"
    private var savedProfile: Data?
    private var savedRegistered: String?

    override func setUp() {
        super.setUp()
        savedProfile = UserDefaults.standard.data(forKey: profileKey)
        savedRegistered = UserDefaults.standard.string(forKey: registeredKey)
        UserDefaults.standard.removeObject(forKey: registeredKey)
        StubURLProtocol.install()
    }

    override func tearDown() {
        ResearchTestSupport.tearDown()
        if let savedProfile {
            UserDefaults.standard.set(savedProfile, forKey: profileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: profileKey)
        }
        if let savedRegistered {
            UserDefaults.standard.set(savedRegistered, forKey: registeredKey)
        } else {
            UserDefaults.standard.removeObject(forKey: registeredKey)
        }
        UserManager.shared.bootstrap()
        super.tearDown()
    }

    private func registerRequests() -> Int {
        StubURLProtocol.requests(to: "student/register").count
    }

    /// 条件在限时内成立即返回；超时算失败
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 3,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("等待超时", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testSignInEntersImmediatelyWhenServerDoesNotAnswer() async throws {
        StubURLProtocol.on("POST", "student/register") { .hang }

        let started = Date()
        try await UserManager.shared.registerStudent(
            appleUserID: "apple-\(UUID().uuidString)", nickname: nil)

        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "登录在等服务器")
        XCTAssertNotNil(UserManager.shared.profile, "本机账号应已建好，可以进首页")
        // 建档请求照样发了，只是在后台
        try await waitUntil { registerRequests() == 1 }
    }

    func testUndeliveredRegistrationIsResentUntilServerAcknowledges() async throws {
        StubURLProtocol.on("POST", "student/register") { .transportError(.timedOut) }
        try await UserManager.shared.registerStudent(
            appleUserID: "apple-\(UUID().uuidString)", nickname: "Amina")
        try await waitUntil { registerRequests() == 1 }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(UserDefaults.standard.string(forKey: registeredKey), "没送达不能记成已送达")

        // 服务器醒了：回到前台时补送
        StubURLProtocol.on("POST", "student/register") { .json(200, [:]) }
        UserManager.shared.syncRegistrationIfNeeded()
        try await waitUntil { UserDefaults.standard.string(forKey: registeredKey) != nil }
        XCTAssertEqual(registerRequests(), 2)

        // 送达之后、档案没变，就不再重复送
        UserManager.shared.syncRegistrationIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(registerRequests(), 2)

        // 改了名字：要重送
        await UserManager.shared.updateNickname("Amina B.")
        XCTAssertEqual(registerRequests(), 3)
        XCTAssertEqual(StubURLProtocol.requests(to: "student/register").last?.body["nickname"] as? String,
                       "Amina B.")
    }

    func testLogoutForgetsDeliveryMarker() async throws {
        StubURLProtocol.on("POST", "student/register") { .json(200, [:]) }
        try await UserManager.shared.registerStudent(
            appleUserID: "apple-\(UUID().uuidString)", nickname: nil)
        try await waitUntil { UserDefaults.standard.string(forKey: registeredKey) != nil }

        UserManager.shared.logout()
        XCTAssertNil(UserDefaults.standard.string(forKey: registeredKey))
    }
}
