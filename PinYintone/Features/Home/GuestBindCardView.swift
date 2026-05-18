import SwiftUI

/// 游客状态提示卡：引导输入班级码绑定
struct GuestBindCardView: View {
    let onBind: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("guest_bind_prompt", comment: ""))
                    .font(.subheadline.weight(.medium))
                Text(NSLocalizedString("guest_bind_subtitle", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(NSLocalizedString("guest_bind_btn", comment: ""), action: onBind)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
