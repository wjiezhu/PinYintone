import Foundation

final class APIClient {
    static let shared = APIClient()
    private init() {}

    // 后端地址：优先读 Info.plist 的 PT_API_BASE_URL（部署后填生产域名），否则回退本地。
    private let baseURL: URL = {
        if let override = Bundle.main.object(forInfoDictionaryKey: "PT_API_BASE_URL") as? String,
           !override.trimmingCharacters(in: .whitespaces).isEmpty,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }()

    // MARK: - Private helpers

    private struct ErrorResponse: Codable { let detail: String }

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

    /// 学生绑定班级码前验证；返回 true = 有效
    func verifyClassCode(_ code: String) async throws -> Bool {
        struct Resp: Codable { let valid: Bool }
        let resp: Resp = try await request("class-code/verify/\(code)")
        return resp.valid
    }

    func registerUser(_ profile: UserProfile) async throws {
        struct Void: Codable {}
        let _: Void = try await request("student/register", method: "POST", body: profile)
    }

    func updateUserBinding(deviceID: String, classCode: String) async throws {
        struct Body: Encodable { let deviceID, classCode: String }
        struct Void: Codable {}
        let _: Void = try await request("student/bind", method: "PUT",
                                        body: Body(deviceID: deviceID, classCode: classCode))
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

    func fetchGroupComparison() async throws -> GroupComparisonData {
        try await request("teacher/class/comparison", token: try await teacherToken())
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
