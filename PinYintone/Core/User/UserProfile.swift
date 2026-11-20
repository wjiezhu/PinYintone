import Foundation

struct UserProfile: Codable {
    let deviceID: String
    var role: UserRole
    var appleUserID: String?       // Sign in with Apple 稳定用户标识；仅 student 有
    var nickname: String?
    var classCode: String?         // 6 位班级码；仅 teacher 有，学生为 nil
    var teacherEmail: String?      // 仅 teacher 角色
    var teacherToken: String?      // JWT Bearer Token；仅 teacher 角色
    var nativeLanguage: String?    // fr / darija / mixed（旧字段，保留兼容）
    /// 学习者会说的语言（多选）。母语迁移分析用。
    /// 2.1（构建 23）之后的版本存 ISO 639 代码（另有 `other`）；2.1 及更早是自定代码，
    /// 对照见 `SpokenLanguage.legacyCodes`
    /// 旧档案无此字段，解码时默认空数组。
    var spokenLanguages: [String]?
    var registeredAt: Date
    /// 学生用邮箱验证码登录时的邮箱（已小写、去空格）；Apple 登录为 nil。
    /// 只存本机用于显示和区分账号，补送档案时不上传（服务端只存它的摘要）。
    var loginEmail: String? = nil

    /// 本机按账号隔离研究状态用的键。Apple 与邮箱是不同的账号，加前缀避免撞在一起。
    var accountKey: String {
        if let appleUserID { return appleUserID }
        if let loginEmail { return "email:" + loginEmail }
        return deviceID
    }
}
