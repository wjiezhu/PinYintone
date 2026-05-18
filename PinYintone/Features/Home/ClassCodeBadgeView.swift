import SwiftUI

/// 已绑定班级码时展示的徽章
struct ClassCodeBadgeView: View {
    let code: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.caption)
            Text(NSLocalizedString("badge_class_code_prefix", comment: ""))
                .font(.caption)
            Text(code)
                .font(.caption.monospaced().bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }
}
