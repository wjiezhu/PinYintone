import XCTest
@testable import PinYintone

/// 登录不等后端建档。
///
/// 服务器慢或连不上时，建档请求要等到 60 秒超时。此前登录要等它返回才进首页，
/// 真机 TestFlight 上表现为「登录一直在转」。
///
/// 这里不经网络栈：把 `UserManager.sendRegistration` 换成假实现（晚 3 秒才完成、或直接失败）。
/// 用 URLProtocol 桩模拟慢服务器时，GitHub 上的模拟器会把等待拖上 30 多秒，结果时好时坏。
@MainActor
final class UserRegistrationTests: XCTestCase {

    private let profileKey = "pt_user_profile"
    private let registeredKey = "pt_registered_profile"
    private var savedProfile: Data?
    private var savedRegistered: String?
    private var savedSender: ((UserProfile) async throws -> Void)!

    /// 假实现收到的每一次建档（含宿主 App 回到前台时 `AppSync` 补送的那次）
    private var sent: [UserProfile] = []
    /// 假实现的行为，用例里随时换
    private var behaviour: () async throws -> Void = {}

    override func setUp() {
        super.setUp()
        savedProfile = UserDefaults.standard.data(forKey: profileKey)
        savedRegistered = UserDefaults.standard.string(forKey: registeredKey)
        UserDefaults.standard.removeObject(forKey: registeredKey)
        savedSender = UserManager.sendRegistration
        sent = []
        behaviour = {}
        UserManager.sendRegistration = { [weak self] p in
            guard let self else { return }
            self.sent.append(p)
            try await self.behaviour()
        }
    }

    override func tearDown() {
        UserManager.sendRegistration = savedSender
        ResearchStore.shared.purgeCurrentAccount()
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

    /// 只数本用例这个账号的建档：宿主 App 回到前台时也可能补送，不数总数
    private func sends(for appleID: String) -> [UserProfile] {
        sent.filter { $0.appleUserID == appleID }
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
        behaviour = { try await Task.sleep(nanoseconds: 3_000_000_000) }
        let appleID = "apple-\(UUID().uuidString)"

        let started = Date()
        try await UserManager.shared.registerStudent(appleUserID: appleID, nickname: nil)

        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "登录在等服务器")
        XCTAssertNotNil(UserManager.shared.profile, "本机账号应已建好，可以进首页")
        // 建档照样完成，只是在后台
        try await waitUntil { delivered }
        XCTAssertFalse(sends(for: appleID).isEmpty)
    }

    func testUndeliveredRegistrationIsResentUntilServerAcknowledges() async throws {
        behaviour = { throw URLError(.timedOut) }
        let appleID = "apple-\(UUID().uuidString)"
        try await UserManager.shared.registerStudent(appleUserID: appleID, nickname: "Amina")
        try await waitUntil { !sends(for: appleID).isEmpty }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(delivered, "没送达不能记成已送达")

        // 服务器醒了：回到前台时补送
        behaviour = {}
        UserManager.shared.syncRegistrationIfNeeded()
        try await waitUntil { delivered }

        // 送达之后、档案没变，就不再重复送
        let count = sends(for: appleID).count
        UserManager.shared.syncRegistrationIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sends(for: appleID).count, count)

        // 改了名字：要重送，送的是新名字
        await UserManager.shared.updateNickname("Amina B.")
        XCTAssertEqual(sends(for: appleID).count, count + 1)
        XCTAssertEqual(sends(for: appleID).last?.nickname, "Amina B.")
    }

    func testLogoutForgetsDeliveryMarker() async throws {
        try await UserManager.shared.registerStudent(
            appleUserID: "apple-\(UUID().uuidString)", nickname: nil)
        try await waitUntil { delivered }

        UserManager.shared.logout()
        XCTAssertFalse(delivered)
    }
}
