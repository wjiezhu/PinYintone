import SwiftUI
import UIKit

/// 教师端顶部：姓名 + 6 位班级码（大字号，可复制/分享）
struct TeacherHeaderView: View {
    let name: String
    let classCode: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name)
                .font(.title2.bold())

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("班级码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(classCode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                Spacer()

                // 复制按钮
                Button {
                    UIPasteboard.general.string = classCode
                    withAnimation(.spring(duration: 0.2)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(copied ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                        .foregroundStyle(copied ? Color.green : Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // 分享按钮
                ShareLink(
                    item: String(
                        format: NSLocalizedString("teacher_classcode_share", comment: ""),
                        classCode
                    )
                ) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
