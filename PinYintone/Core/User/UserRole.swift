import Foundation

enum UserRole: String, Codable {
    case student  // 学生（只填名字注册，后端均衡分配 A/B）
    case teacher  // 已注册教师账户
}
