import Foundation

struct UserProfile: Codable {
    let deviceID: String
    var role: UserRole
    var appleUserID: String?       // Sign in with Apple 稳定用户标识；仅 student 有
    var nickname: String?
    var classCode: String?         // 6 位班级码；仅 teacher 有，学生为 nil
    var teacherEmail: String?      // 仅 teacher 角色
    var teacherToken: String?      // JWT Bearer Token；仅 teacher 角色
    var experimentGroup: String    // "staticColor" | "dynamicF0" | "n/a"
    var nativeLanguage: String?    // fr / darija / mixed
    var registeredAt: Date
}
