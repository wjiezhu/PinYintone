import SwiftUI

/// 学生主页顶部问候横幅：昵称 + 今日练习提示
struct HeaderBannerView: View {
    let nickname: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(NSLocalizedString("home_practice_subtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        if let name = nickname, !name.isEmpty {
            return String(format: NSLocalizedString("home_greeting_name", comment: ""), name)
        }
        return NSLocalizedString("home_greeting", comment: "")
    }
}
