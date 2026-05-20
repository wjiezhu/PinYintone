import SwiftUI

/// 单个词条芯片：汉字 + 拼音注音 + 删除按钮。
struct TokenChipView: View {
    let token: String
    let pinyin: String
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: 1) {
                Text(pinyin)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(token)
                    .font(.body.weight(.medium))
            }
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onTap)
    }
}
