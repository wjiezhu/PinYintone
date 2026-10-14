import XCTest
@testable import PinYintone

/// 登录不等后端建档。
///
/// 服务器慢或连不上时，建档请求要等到 60 秒超时。此前登录要等它返回才进首页，
/// 真机 TestFlight 上表现为「登录一直在转」。这里用晚 3 秒才回的假服务器复现。
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

    /// 只数**本用例这个账号**发出的建档请求。
    ///
    /// 宿主 App 回到前台时也会补送一次（`AppSync.run`），别的用例留下的请求也可能晚到，
    /// 所以不数总数，只数带着本用例 Apple 标识的那几条。
    private func registerRequests(for appleID: String) -> [StubURLProtocol.Recorded] {
        StubURLProtocol.requests(to: "student/register")
            .filter { $0.body["appleUserID"] as? String == appleID }
    }

    private var delivered: Bool { UserDefaults.standard.string(forKey: registeredKey) != nil }

    /// 条件在限时内成立即返回；超时算失败
    private func waitUntil(timeout: TimeInterval = 10,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("等待超时", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testSignInEntersImmediatelyWhenServerIsSlow() async throws {
        // 服务器 3 秒后才回：旧写法下登录要等满这 3 秒
        StubURLProtocol.on("POST", "student/register") { .delayed(3, 200, [:]) }
        let appleID = "apple-\(UUID().uuidString)"

        let started = Date()
        try await UserManager.shared.registerStudent(appleUserID: appleID, nickname: nil)

        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "登录在等服务器")
        XCTAssertNotNil(UserManager.shared.profile, "本机账号应已建好，可以进首页")
        // 建档照样完成，只是在后台
        try await waitUntil { delivered }
        XCTAssertFalse(registerRequests(for: appleID).isEmpty)
    }

    func testUndeliveredRegistrationIsResentUntilServerAcknowledges() async throws {
        StubURLProtocol.on("POST", "student/register") { .transportError(.timedOut) }
        let appleID = "apple-\(UUID().uuidString)"
        try await UserManager.shared.registerStudent(appleUserID: appleID, nickname: "Amina")
        try await waitUntil { !registerRequests(for: appleID).isEmpty }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(delivered, "没送达不能记成已送达")

        // 服务器醒了：回到前台时补送
        StubURLProtocol.on("POST", "student/register") { .json(200, [:]) }
        UserManager.shared.syncRegistrationIfNeeded()
        try await waitUntil { delivered }

        // 送达之后、档案没变，就不再重复送
        let sent = registerRequests(for: appleID).count
        UserManager.shared.syncRegistrationIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(registerRequests(for: appleID).count, sent)

        // 改了名字：要重送，送的是新名字
        await UserManager.shared.updateNickname("Amina B.")
        XCTAssertEqual(registerRequests(for: appleID).count, sent + 1)
        XCTAssertEqual(registerRequests(for: appleID).last?.body["nickname"] as? String, "Amina B.")
    }

    func testLogoutForgetsDeliveryMarker() async throws {
        StubURLProtocol.on("POST", "student/register") { .json(200, [:]) }
        try await UserManager.shared.registerStudent(
            appleUserID: "apple-\(UUID().uuidString)", nickname: nil)
        try await waitUntil { delivered }

        UserManager.shared.logout()
        XCTAssertFalse(delivered)
    }
}
