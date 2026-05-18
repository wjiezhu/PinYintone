import Foundation

final class APIClient {
    static let shared = APIClient()
    private init() {}

    // 后端地址；正式部署时通过 Info.plist 或环境变量覆盖
    private let baseURL = URL(string: "http://localhost:8000")!

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

    // MARK: - Sync (Chapter 3)

    func syncSession(_ session: TrainingSession) async throws {
        fatalError("TODO: 第三章实现")
    }

    func syncAspiration(_ attempt: AspirationAttempt) async throws {
        fatalError("TODO: 第三章实现")
    }

    func syncFreeText(_ record: FreeTextRecord) async throws {
        fatalError("TODO: 第三章实现")
    }

    // MARK: - Teacher Dashboard (Chapter 4)

    func fetchClassSummary() async throws -> ClassSummary {
        fatalError("TODO: 第四章实现")
    }

    func fetchGroupComparison() async throws -> GroupComparisonData {
        fatalError("TODO: 第四章实现")
    }

    func fetchToneBreakdown() async throws -> ToneBreakdownData {
        fatalError("TODO: 第四章实现")
    }

    func fetchStudents() async throws -> [StudentRowData] {
        fatalError("TODO: 第四章实现")
    }

    func fetchStudentDetail(deviceID: String) async throws -> StudentDetailData {
        fatalError("TODO: 第四章实现")
    }

    func exportClassCSV() async throws -> URL {
        fatalError("TODO: 第四章实现")
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
