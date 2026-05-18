import Foundation

struct UserProfile: Codable {
    let deviceID: String
    var role: UserRole
    var nickname: String?
    var classCode: String?         // 6 位班级码；guest 为 nil
    var teacherEmail: String?      // 仅 teacher 角色
    var teacherToken: String?      // JWT Bearer Token；仅 teacher 角色
    var experimentGroup: String    // "staticColor" | "dynamicF0" | "n/a"
    var nativeLanguage: String?    // fr / darija / mixed
    var registeredAt: Date
}
