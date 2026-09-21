import Foundation

final class APIClient {
    static let shared = APIClient()
    private init() {}

    // 后端地址：优先读打包资源 APIConfig.plist 的 BaseURL（部署后填生产域名），
    // 其次 Info.plist 的 PT_API_BASE_URL，最后回退本地。
    private let baseURL: URL = {
        func parse(_ s: String?) -> URL? {
            guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return URL(string: s)
        }
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
    private struct ResearchEventAck: Decodable { let received: Int; let inserted: Int }

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
    private func researchRequest<T: Decodable>(
        _ path: String, method: String = "GET", body: (any Encodable)? = nil
    ) async throws -> T {
        try await request(path, method: method, body: body,
                          encoder: ResearchJSON.encoder, decoder: ResearchJSON.decoder)
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

    /// 删除账号：清除服务端该用户及其全部训练数据。
    struct EnrollResearchResponse: Decodable {
        let participantID: String
        let studyID: String
        let alreadyEnrolled: Bool
    }

    /// 纳入研究。返回的 participantID 由**服务端**随机生成，
    /// 客户端不得自行构造或从账号键派生（字典 §4）。
    func enrollResearch(internalUserID: String, manifestID: String,
                        consentVersion: String, consentLanguage: String,
                        consentOccurredAt: Date, isTest: Bool) async throws -> EnrollResearchResponse {
        struct Body: Encodable {
            let internalUserID: String, manifestID: String
            let consentVersion: String, consentLanguage: String
            let consentOccurredAt: Date
            let isTest: Bool
        }
        return try await researchRequest("research/enroll", method: "POST",
                                 body: Body(internalUserID: internalUserID,
                                            manifestID: manifestID,
                                            consentVersion: consentVersion,
                                            consentLanguage: consentLanguage,
                                            consentOccurredAt: consentOccurredAt,
                                            isTest: isTest))
    }

    /// 撤回研究同意。服务端**追加**一条 withdrawn，不改写历史。
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
    }

    /// 取当前生效的研究配置。404 表示暂无生效配置——
    /// 此时不得纳入任何人，也不得猜一个配置。
    func fetchActiveManifest() async throws -> ActiveManifest {
        try await researchRequest("research/manifest/active")
    }

    /// 上报练习尝试。失败抛错由调用方保留队列重试。
    func uploadResearchAttempts(_ batch: any Encodable) async throws {
        let _: ResearchEventAck = try await researchRequest("research/attempts",
                                                    method: "POST", body: batch)
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

    /// 上报一份问卷（实例 + 逐题答案）。
    func uploadSurvey(participantID: String, manifestID: String,
                      outcome: SurveyOutcome, timingClass: String,
                      qualifyingAttemptsAtInvite: Int) async throws {
        struct Body: Encodable {
            let participantID: String, manifestID: String
            let outcome: SurveyOutcome
            let timingClass: String
            let qualifyingAttemptsAtInvite: Int
        }
        struct Ack: Decodable { let surveyInstanceID: String }
        let _: Ack = try await researchRequest("research/surveys", method: "POST",
                                       body: Body(participantID: participantID,
                                                  manifestID: manifestID,
                                                  outcome: outcome,
                                                  timingClass: timingClass,
                                                  qualifyingAttemptsAtInvite: qualifyingAttemptsAtInvite))
    }

    /// 上报研究操作事件。失败抛错由调用方保留队列重试——
    /// **不得**在这里吞掉错误，否则离线期间的事件会静默丢失。
    func uploadResearchEvents(_ batch: any Encodable) async throws {
        let _: ResearchEventAck = try await researchRequest("research/events",
                                                    method: "POST", body: batch)
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
