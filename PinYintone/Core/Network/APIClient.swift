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
        token: String? = nil
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONEncoder().encode(body) }

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
        return try JSONDecoder().decode(T.self, from: data)
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
        return try await request("research/enroll", method: "POST",
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
        let _: Ack = try await request("research/withdraw", method: "POST",
                                       body: Body(participantID: participantID,
                                                  consentVersion: consentVersion,
                                                  consentLanguage: consentLanguage,
                                                  occurredAt: occurredAt))
    }

    /// 上报一份问卷（实例 + 逐题答案）。
    func uploadSurvey(participantID: String, manifestID: String,
                      outcome: SurveyOutcome) async throws {
        struct Body: Encodable {
            let participantID: String, manifestID: String
            let outcome: SurveyOutcome
        }
        struct Ack: Decodable { let surveyInstanceID: String }
        let _: Ack = try await request("research/surveys", method: "POST",
                                       body: Body(participantID: participantID,
                                                  manifestID: manifestID,
                                                  outcome: outcome))
    }

    /// 上报研究操作事件。失败抛错由调用方保留队列重试——
    /// **不得**在这里吞掉错误，否则离线期间的事件会静默丢失。
    func uploadResearchEvents(_ batch: any Encodable) async throws {
        let _: ResearchEventAck = try await request("research/events",
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
