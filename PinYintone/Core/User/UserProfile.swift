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
    var nativeLanguage: String?    // fr / darija / mixed（旧字段，保留兼容）
    /// 学习者会说的语言（多选，SpokenLanguage.rawValue）。母语迁移分析用。
    /// 旧档案无此字段，解码时默认空数组。
    var spokenLanguages: [String]?
    var registeredAt: Date
}
