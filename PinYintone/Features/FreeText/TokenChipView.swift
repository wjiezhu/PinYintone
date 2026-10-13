import SwiftUI

/// 单个词条芯片：汉字 + 拼音注音 + 删除按钮。
struct TokenChipView: View {
    let token: String
    let pinyin: String
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 1) {
                Text(pinyin)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(token)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.leading, Theme.Space.m)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: Theme.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("delete", comment: ""))
        }
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.divider))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        .environment(\.layoutDirection, .leftToRight)
        .onTapGesture(perform: onTap)
    }
}
