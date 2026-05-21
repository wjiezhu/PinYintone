import SwiftUI

/// 使用说明（被试可随时点主页右下角「i」查看）。文案随 App 语言本地化。
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                section(icon: "wind", color: .teal,
                        title: NSLocalizedString("stage1_title", comment: ""),
                        body: NSLocalizedString("help_stage1_body", comment: ""))
                section(icon: "waveform.and.mic", color: .blue,
                        title: NSLocalizedString("stage2_title", comment: ""),
                        body: NSLocalizedString("help_stage2_body", comment: ""))
                section(icon: "text.bubble", color: .purple,
                        title: NSLocalizedString("stage3_title", comment: ""),
                        body: NSLocalizedString("help_stage3_body", comment: ""))

                Section {
                    label("lightbulb", .orange, NSLocalizedString("help_tip", comment: ""))
                    label("lock.shield", .green, NSLocalizedString("help_privacy", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("help_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("settings_done", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func section(icon: String, color: Color, title: String, body: String) -> some View {
        Section {
            Text(body).font(.subheadline)
        } header: {
            Label(title, systemImage: icon).foregroundStyle(color)
        }
    }

    private func label(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            Text(text).font(.subheadline)
        }
    }
}
