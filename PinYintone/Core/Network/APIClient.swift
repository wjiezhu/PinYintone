import Foundation

final class APIClient {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = APIClient()
    private init() {}

    // 后端地址：优先读打包资源 APIConfig.plist 的 BaseURL（部署后填生产域名），
    // 其次 Info.plist 的 PT_API_BASE_URL，最后回退本地。
    private let baseURL: URL = {
        func parse(_ s: String?) -> URL? {
            guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return URL(string: s)
        }
        #if DEBUG
        // 仅开发构建：用启动环境变量把后端指到本地测试服务，
        // 这样界面测试与对账验收不碰线上数据。正式构建里这段代码不存在。
        if let parsed = parse(ProcessInfo.processInfo.environment["PT_API_BASE_URL"]) {
            return parsed
        }
        // 作为单元测试的宿主启动时，**绝不连线上**：指到一个不通的本地地址。
        // 宿主启动会跑一遍自动同步；本机若留有测试产生的未同步记录，
        // 默认地址会把它们传到线上业务表里（2026-10-13 实际发生过）。
        if TestHost.isRunningUnitTests {
            return URL(string: "http://127.0.0.1:9")!
        }
        #endif
        if let url = Bundle.main.url(forResource: "APIConfig", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let parsed = parse(dict["BaseURL"] as? String) {
            return parsed
        }
        if let parsed = parse(Bundle.main.object(forInfoDictionaryKey: "PT_API_BASE_URL") as? String) {
            return parsed
        }
        return URL(string: "http://localhost:8000")!
    }()

    // MARK: - Private helpers

    private struct ErrorResponse: Codable { let detail: String }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        token: String? = nil,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try encoder.encode(body) }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw RegisterError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 400,
           let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            if err.detail.contains("邮箱") || err.detail.lowercased().contains("email") {
                throw RegisterError.emailAlreadyExists
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RegisterError.networkError(URLError(.badServerResponse))
        }
        return try decoder.decode(T.self, from: data)
    }

    /// 研究接口专用：日期一律 ISO8601。**所有 research/ 路径必须走这里**——
    /// 见 `ResearchJSON` 的说明，默认编码会让时间错 31 年且全程静默。
    ///
    /// 错误统一抛 `ResearchAPIError`，把「传输失败」与「服务端明确拒绝」分开：
    /// 前者稍后原样重试，后者重试也没用。此前两者都被包成同一个网络错误，
    /// 上传队列分不清该等还是该放弃。
    private func researchRequest<T: Decodable>(
        _ path: String, method: String = "GET", query: [URLQueryItem] = [],
        body: (any Encodable)? = nil
    ) async throws -> T {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)
        if !query.isEmpty { comps?.queryItems = query }
        guard let url = comps?.url else { throw ResearchAPIError.transport(URLError(.badURL)) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            if let body { req.httpBody = try ResearchJSON.encoder.encode(body) }
        } catch {
            throw ResearchAPIError.encoding(error)
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ResearchAPIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ResearchAPIError.transport(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
            throw ResearchAPIError.http(status: http.statusCode, detail: detail)
        }
        do {
            return try ResearchJSON.decoder.decode(T.self, from: data)
        } catch {
            throw ResearchAPIError.decoding(error)
        }
    }

    // MARK: - Auth

    func registerTeacher(email: String, password: String, name: String) async throws -> TeacherRegisterResponse {
        struct Body: Encodable { let email, password, name: String }
        return try await request("teacher/register", method: "POST",
                                 body: Body(email: email, password: password, name: name))
    }

    func loginTeacher(email: String, password: String) async throws -> TeacherLoginResponse {
        struct Body: Encodable { let email, password: String }
        return try await request("teacher/login", method: "POST",
                                 body: Body(email: email, password: password))
    }

    /// 学生注册（Sign in with Apple，无需班级码）。
    ///
    /// 幂等建档；不再返回任何实验分组信息。
    @discardableResult
    func registerUser(_ profile: UserProfile) async throws -> StudentRegistration {
        try await request("student/register", method: "POST", body: profile)
    }

    // MARK: - Research

    struct EnrollResearchResponse: Decodable {
        let participantID: String
        let studyID: String
        let alreadyEnrolled: Bool
    }

    /// 纳入研究。返回的 participantID 由**服务端**随机生成，
    /// 客户端不得自行构造或从账号键派生（字典 §4）。
    ///
    /// 调用前提：已有业务账号（服务端按它去重，同账号换设备返回同一编号）、
    /// 端侧已判定合格。使用史如实上报，识别不了就是 unknown。
    func enrollResearch(internalUserID: String, manifestID: String,
                        consentVersion: String, consentLanguage: String,
                        consentOccurredAt: Date, eligibilityVersion: String,
                        priorUse: PriorUse, isTest: Bool) async throws -> EnrollResearchResponse {
        struct Body: Encodable {
            let internalUserID: String, manifestID: String
            let consentVersion: String, consentLanguage: String
            let consentOccurredAt: Date
            let eligibilityStatus: String, eligibilityVersion: String
            let priorUseStatus: String, priorUseEvidence: String
            let isTest: Bool
        }
        return try await researchRequest("research/enroll", method: "POST",
                                         body: Body(internalUserID: internalUserID,
                                                    manifestID: manifestID,
                                                    consentVersion: consentVersion,
                                                    consentLanguage: consentLanguage,
                                                    consentOccurredAt: consentOccurredAt,
                                                    eligibilityStatus: "eligible",
                                                    eligibilityVersion: eligibilityVersion,
                                                    priorUseStatus: priorUse.status.rawValue,
                                                    priorUseEvidence: priorUse.evidence.rawValue,
                                                    isTest: isTest))
    }

    /// 退出研究。服务端**追加**一条 withdrawn，不改写历史；重复调用幂等。
    func withdrawResearch(participantID: String, consentVersion: String,
                          consentLanguage: String, occurredAt: Date) async throws {
        struct Body: Encodable {
            let participantID: String, consentVersion: String
            let consentLanguage: String
            let occurredAt: Date
        }
        struct Ack: Decodable { let status: String }
        let _: Ack = try await researchRequest("research/withdraw", method: "POST",
                                               body: Body(participantID: participantID,
                                                          consentVersion: consentVersion,
                                                          consentLanguage: consentLanguage,
                                                          occurredAt: occurredAt))
    }

    struct ActiveManifest: Decodable {
        let manifestID: String
        let studyID: String
        let collectionStartAt: Date
        let collectionEndAt: Date
        let postTriggerCount: Int
        let consentVersion: String
        let surveyVersion: String
        /// 为空表示积分功能未上线
        let rewardRuleVersion: String?
        // 以下供客户端自检（见 ResearchConfig.incompatibility）
        let appVersion: String?
        let buildNumber: String?
        let lexiconVersion: String?
        let eligibilityVersion: String?
        let surveyForms: [String: [String: String]]?
        let isTest: Bool?
        /// 现场实测协议；为空 = 这份配置不提供现场实测
        var fieldProtocolVersion: String? = nil
        var fieldProtocol: FieldProtocolSpec? = nil
        /// 是否接收录音。还要参与者同意的文本含录音，才真的上传
        var audioUpload: Bool? = nil
    }

    /// 配置里绑定的实测协议（服务端字段名是 snake_case）
    nonisolated struct FieldProtocolSpec: Codable, Equatable {
        let lexiconVersion: String
        let testLexemeVersionIDs: [String]
        let trainingLexemeVersionIDs: [String]
        let trainingValidAttemptsPerWord: Int

        enum CodingKeys: String, CodingKey {
            case lexiconVersion = "lexicon_version"
            case testLexemeVersionIDs = "test_lexeme_version_ids"
            case trainingLexemeVersionIDs = "training_lexeme_version_ids"
            case trainingValidAttemptsPerWord = "training_valid_attempts_per_word"
        }
    }

    /// 取与本构建匹配的当前生效研究配置。404 表示暂无——
    /// 此时不得纳入任何人，也不得猜一个配置。
    func fetchActiveManifest(appVersion: String, build: String,
                             test: Bool) async throws -> ActiveManifest {
        try await researchRequest("research/manifest/active", query: [
            .init(name: "appVersion", value: appVersion),
            .init(name: "build", value: build),
            .init(name: "test", value: test ? "true" : "false"),
        ])
    }

    /// 批量上报的回执。`rejected` 里是服务端明确不收的记录（窗口外、归属不符等），
    /// 重传也不会被接受——客户端据此把它们移出队列，而不是让一条坏记录堵死全部。
    struct BatchAck: Decodable {
        struct Rejected: Decodable { let id: String; let reason: String }
        let received: Int
        let inserted: Int
        let duplicates: Int?
        let rejected: [Rejected]?
    }

    /// 上报练习尝试。失败抛错由调用方保留队列重试。
    func uploadResearchAttempts(_ batch: any Encodable) async throws -> BatchAck {
        try await researchRequest("research/attempts", method: "POST", body: batch)
    }

    /// 上报研究操作事件。失败抛错由调用方保留队列重试——
    /// **不得**在这里吞掉错误，否则离线期间的事件会静默丢失。
    func uploadResearchEvents(_ batch: any Encodable) async throws -> BatchAck {
        try await researchRequest("research/events", method: "POST", body: batch)
    }

    struct RecordingAck: Decodable { let status: String }

    /// 上传一次尝试的录音（AAC ADTS，base64 放在 JSON 里）。
    func uploadResearchRecording(_ body: any Encodable) async throws -> RecordingAck {
        try await researchRequest("research/recordings", method: "POST", body: body)
    }

    /// 上报「练习建议」点击记录。
    func uploadResearchAdvice(_ batch: any Encodable) async throws -> BatchAck {
        try await researchRequest("research/advice", method: "POST", body: batch)
    }

    /// 报告问题。report_id 为幂等键，网络重传不产生重复报告。
    func reportIssue(reportID: String, participantID: String, manifestID: String,
                     submittedAt: Date, category: String, detail: String?) async throws {
        struct Body: Encodable {
            let reportID: String, participantID: String, manifestID: String
            let submittedAt: Date, category: String, detail: String?
        }
        struct Ack: Decodable { let reportID: String }
        let _: Ack = try await researchRequest("research/issues", method: "POST",
                                               body: Body(reportID: reportID,
                                                          participantID: participantID,
                                                          manifestID: manifestID,
                                                          submittedAt: submittedAt,
                                                          category: category, detail: detail))
    }

    struct SurveyAck: Decodable {
        let surveyInstanceID: String
        let alreadySubmitted: Bool
        /// 服务端此刻保存的状态。以它为准判断「是否已提交」。
        let status: String?
        let updated: Bool?
    }

    /// 上报一份问卷的当前状态（实例 + 逐题答案）。
    ///
    /// 邀请时间、邀请时合格次数、语言、表单与译文版本都取自**实例里的快照**，
    /// 不是此刻的值——重试上传不改变它们。
    func uploadSurvey(_ record: SurveyRecord, timingClass: String,
                      participantID: String, manifestID: String) async throws -> SurveyAck {
        struct Outcome: Encodable {
            let formKey: String, formVersion: String, translationVersion: String
            let language: String
            let answers: [SurveyAnswer]
            let status: String
            let startedAt: Date?, submittedAt: Date?
        }
        struct Body: Encodable {
            let participantID: String, manifestID: String
            let surveyInstanceID: String
            let invitedAt: Date
            let outcome: Outcome
            let timingClass: String
            let qualifyingAttemptsAtInvite: Int
        }
        return try await researchRequest("research/surveys", method: "POST", body: Body(
            participantID: participantID, manifestID: manifestID,
            surveyInstanceID: record.instanceID.uuidString,
            invitedAt: record.invitedAt,
            outcome: Outcome(formKey: record.formKey, formVersion: record.formVersion,
                             translationVersion: record.translationVersion,
                             language: record.language,
                             answers: record.status.isFinal ? record.answers : [],
                             status: record.status.rawValue,
                             startedAt: record.startedAt,
                             submittedAt: record.status.isFinal ? record.submittedAt : nil),
            timingClass: timingClass,
            qualifyingAttemptsAtInvite: record.qualifyingAttemptsAtInvite))
    }

    /// App Store 审核指南 5.1.1(v) 强制要求；亦作为研究伦理的「撤回同意」通道。
    func deleteAccount(deviceID: String, appleUserID: String?) async throws {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("student/account"),
            resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "deviceID", value: deviceID)]
        if let appleUserID, !appleUserID.isEmpty {
            items.append(URLQueryItem(name: "appleUserID", value: appleUserID))
        }
        comps?.queryItems = items
        guard let url = comps?.url else {
            throw RegisterError.networkError(URLError(.badURL))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw RegisterError.networkError(URLError(.badServerResponse))
        }
    }

    // MARK: - Sync（数据上行，POST /api/sync/*）

    private struct SyncAck: Codable {}   // 后端返回 {} 即视为成功

    func syncSession(_ dto: TrainingSessionDTO) async throws {
        let _: SyncAck = try await request("api/sync/session", method: "POST", body: dto)
    }

    func syncAspiration(_ dto: AspirationAttemptDTO) async throws {
        let _: SyncAck = try await request("api/sync/aspiration", method: "POST", body: dto)
    }

    func syncFreeText(_ dto: FreeTextRecordDTO) async throws {
        let _: SyncAck = try await request("api/sync/freetext", method: "POST", body: dto)
    }

    // MARK: - Teacher Dashboard (Chapter 4)

    /// 教师面板接口需 Bearer Token；从当前登录档案读取
    private func teacherToken() async throws -> String {
        guard let token = await MainActor.run(body: { UserManager.shared.profile?.teacherToken }) else {
            throw RegisterError.networkError(URLError(.userAuthenticationRequired))
        }
        return token
    }

    func fetchClassSummary() async throws -> ClassSummary {
        try await request("teacher/class/summary", token: try await teacherToken())
    }


    func fetchToneBreakdown() async throws -> ToneBreakdownData {
        try await request("teacher/class/tone-breakdown", token: try await teacherToken())
    }

    func fetchStudents() async throws -> [StudentRowData] {
        try await request("teacher/students", token: try await teacherToken())
    }

    func fetchStudentDetail(deviceID: String) async throws -> StudentDetailData {
        try await request("teacher/students/\(deviceID)", token: try await teacherToken())
    }

    /// 直接下载后端生成的 CSV 至临时文件，返回本地 URL
    func exportClassCSV() async throws -> URL {
        let token = try await teacherToken()
        var req = URLRequest(url: baseURL.appendingPathComponent("teacher/export/csv"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RegisterError.networkError(URLError(.badServerResponse))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinyintone_class.csv")
        try data.write(to: url)
        return url
    }
}

// MARK: - Response Types

struct TeacherRegisterResponse: Codable {
    let classCode: String
    let token: String
    let teacherID: Int
}

struct TeacherLoginResponse: Codable {
    let token: String
    let teacherID: Int
    let classCode: String
}

/// 研究接口的错误。区分「稍后重试有意义」与「重试也没用」。
enum ResearchAPIError: Error {
    /// 没连上、超时、连接中断
    case transport(Error)
    /// 服务端给了明确的非 2xx 回答
    case http(status: Int, detail: String?)
    case encoding(Error)
    case decoding(Error)

    /// 稍后原样重试是否可能成功。
    /// 传输失败、服务端临时故障（5xx）、超时与限流可以重试；
    /// 其余 4xx 是服务端对**这份数据**的明确拒绝，重试只会得到同样的回答。
    var isRetryable: Bool {
        switch self {
        case .transport: return true
        case .http(let status, _): return status >= 500 || status == 408 || status == 429
        case .encoding, .decoding: return false
        }
    }

    /// 服务端拒绝时给出的机读原因（`detail` 冒号前的部分），如 `no_active_consent`
    var reasonCode: String? {
        guard case .http(_, let detail?) = self else { return nil }
        let head = detail.split(whereSeparator: { $0 == "：" || $0 == ":" }).first.map(String.init)
        return head?.trimmingCharacters(in: .whitespaces)
    }

    var status: Int? {
        if case .http(let status, _) = self { return status }
        return nil
    }
}

#if DEBUG
/// 仅开发构建：当前进程是不是单元测试的宿主。正式构建里不存在。
///
/// 宿主进程会像正常启动一样跑自动同步，所以它必须与线上后端、与 App 的正式本机数据都隔开：
/// 后端指到不通的地址（见 `APIClient`），本机记录用内存库（见 `CoreDataStack`）。
enum TestHost {
    static let isRunningUnitTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
#endif
