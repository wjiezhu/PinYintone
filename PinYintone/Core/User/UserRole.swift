import Foundation

enum UserRole: String, Codable {
    case guest    // 未绑定班级码
    case student  // 已绑定班级码
    case teacher  // 已注册教师账户
}
