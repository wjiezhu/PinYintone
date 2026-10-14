import Foundation
import XCTest
@testable import PinYintone

/// 研究相关测试共用的脚手架。
///
/// 每个测试用一个**全新的测试账号**：研究状态按账号隔离存储，
/// 换一个账号键就是一份干净的状态，测试之间互不串。
@MainActor
enum ResearchTestSupport {

    static let now = Date()

    /// 切到一个全新的账号（研究状态为空、队列为空）
    @discardableResult
    static func freshAccount() -> String {
        let key = "test-\(UUID().uuidString)"
        ResearchStore.shared.activate(accountKey: key)
        // 单元测试里由测试自己决定何时上传：自动上传是延时触发的，
        // 不关掉的话会落到后面别的用例里，把那边的请求计数搅乱
        ResearchUploader.shared.autoFlushDelay = nil
        return key
    }

    /// 全新账号，并置为「服务端已确认纳入、此刻在采集窗口内、背景表已送达」
    @discardableResult
    static func enrolledAccount(windowStart: Date = Date().addingTimeInterval(-3600),
                                windowEnd: Date = Date().addingTimeInterval(86_400),
                                backgroundAcked: Bool = true) -> String {
        let key = freshAccount()
        ResearchStore.shared.update { s in
            s.participation = .enrolled
            s.eligibility = "eligible"
            s.consentVersion = ResearchConsent.textVersion
            s.consentLanguage = "fr"
            s.consentAt = Date().addingTimeInterval(-600)
            s.participantID = "participant-test"
            s.manifestID = "manifest-test"
            s.studyID = "study-test"
            s.windowStart = windowStart
            s.windowEnd = windowEnd
            s.postTriggerCount = 5
            var bg = SurveyRecord(
                instanceID: UUID(), formKey: SurveyCenter.backgroundKey,
                formVersion: "bg", translationVersion: "t", language: "fr",
                invitedAt: Date().addingTimeInterval(-600), qualifyingAttemptsAtInvite: 0,
                status: .complete, submittedAt: Date().addingTimeInterval(-590),
                timingClass: "background")
            bg.syncedStatus = backgroundAcked ? .complete : nil
            s.surveys[SurveyCenter.backgroundKey] = bg
        }
        return key
    }

    /// 清掉当前测试账号的全部研究状态，回到未登录
    static func tearDown() {
        ResearchStore.shared.purgeCurrentAccount()
        ResearchConfig.shared.setAvailableForTesting(nil)
        StubURLProtocol.reset()
    }

    static func manifest(start: Date = Date().addingTimeInterval(-3600),
                         end: Date = Date().addingTimeInterval(86_400),
                         isTest: Bool = true) -> ResearchConfig.Manifest {
        .init(manifestID: "manifest-test", studyID: "study-test",
              collectionStartAt: start, collectionEndAt: end, postTriggerCount: 5,
              consentVersion: ResearchConsent.textVersion, rewardRuleVersion: nil,
              isTest: isTest)
    }

    /// 符合纳入条件的背景答卷（成年、MA、hsk2）
    static func background(adult: String? = "adult", nationality: [String]? = ["MA"],
                           stage: String? = "hsk2",
                           startedAt: Date = Date().addingTimeInterval(-120),
                           submittedAt: Date = Date().addingTimeInterval(-60)) -> SurveyOutcome {
        func answer(_ q: String, _ codes: [String]?) -> SurveyAnswer {
            guard let codes else {
                return SurveyAnswer(questionID: q, state: .skipped, optionCodes: nil,
                                    textValue: nil, answeredAt: submittedAt)
            }
            return SurveyAnswer(questionID: q, state: .answered, optionCodes: codes,
                                textValue: nil, answeredAt: submittedAt)
        }
        let answers = [answer("B01", adult.map { [$0] }), answer("B02", nationality),
                       answer("B03", stage.map { [$0] })]
        return SurveyOutcome(formKey: SurveyCenter.backgroundKey, formVersion: "bg-test",
                             translationVersion: "t-test", language: "fr", answers: answers,
                             status: SurveyCenter.status(for: answers).rawValue,
                             startedAt: startedAt, submittedAt: submittedAt)
    }

    static func profile(appleID: String = "apple-test") -> UserProfile {
        UserProfile(deviceID: "device-test", role: .student, appleUserID: appleID,
                    nickname: nil, classCode: nil, teacherEmail: nil, teacherToken: nil,
                    nativeLanguage: nil, spokenLanguages: [], registeredAt: Date())
    }
}

/// 拦截发往后端的请求，按预先排好的脚本作答，并记下每个请求的内容。
///
/// 用它而不是真服务器，是为了能精确造出「断网」「超时」「5xx」「服务端明确拒绝」
/// 这些情形，并检查 App **实际发出去的** JSON 字段——接口脚本自己拼的请求体
/// 证明不了 App 发的是对的（事件名字段就这样错过一次）。
final class StubURLProtocol: URLProtocol {

    struct Recorded {
        let method: String
        let path: String
        let query: [String: String]
        let body: [String: Any]
    }

    enum Reply {
        case json(Int, Any)
        case transportError(URLError.Code)
    }

    nonisolated(unsafe) private static var handlers: [(matches: (String, String) -> Bool, reply: () -> Reply)] = []
    nonisolated(unsafe) private static var recorded: [Recorded] = []
    nonisolated(unsafe) private static var installed = false
    private static let lock = NSLock()

    /// 开始拦截。之后未被 `on` 匹配到的请求一律按断网处理——测试不许真的联网。
    static func install() {
        lock.withLock {
            if !installed {
                URLProtocol.registerClass(StubURLProtocol.self)
                installed = true
            }
        }
    }

    static func reset() {
        lock.withLock {
            handlers = []
            recorded = []
            if installed {
                URLProtocol.unregisterClass(StubURLProtocol.self)
                installed = false
            }
        }
    }

    /// 路径以 `suffix` 结尾的请求按 `reply` 作答。后登记的优先。
    static func on(_ method: String = "POST", _ suffix: String, reply: @escaping () -> Reply) {
        lock.withLock {
            handlers.insert((matches: { m, p in m == method && p.hasSuffix(suffix) },
                             reply: reply), at: 0)
        }
    }

    static var requests: [Recorded] { lock.withLock { recorded } }
    static func requests(to suffix: String) -> [Recorded] {
        requests.filter { $0.path.hasSuffix(suffix) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let url = request.url!
        let path = url.path
        var query: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.forEach {
            query[$0.name] = $0.value
        }
        let data = request.httpBody ?? Self.read(request.httpBodyStream)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        let reply: Reply = Self.lock.withLock {
            Self.recorded.append(Recorded(method: method, path: path, query: query, body: body))
            return Self.handlers.first { $0.matches(method, path) }?.reply()
                ?? .transportError(.notConnectedToInternet)
        }
        switch reply {
        case .transportError(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .json(let status, let object):
            let payload = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: payload)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buffer, maxLength: 4096)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

extension StubURLProtocol {
    /// 常用回执
    static func batchOK(rejected: [[String: String]] = []) -> Reply {
        .json(200, ["received": 1, "inserted": 1, "duplicates": 0, "rejected": rejected])
    }
}
