import SwiftUI

/// CSV 导出按钮；点击后调用 TeacherDashboardViewModel.exportCSV()
struct ExportButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("导出 CSV", systemImage: "square.and.arrow.up.on.square")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
