import SwiftUI

/// 使用说明（设置页进入）。文案随 App 语言本地化。
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    GroupedCard {
                        topic(icon: "waveform", title: "stage2_title", body: "help_stage2_body")
                        RowDivider()
                        topic(icon: "text.cursor", title: "stage3_title", body: "help_stage3_body")
                        RowDivider()
                        topic(icon: "wind", title: "stage1_title", body: "help_stage1_body")
                    }
                    GroupedCard {
                        note(icon: "lightbulb", text: "help_tip")
                        RowDivider()
                        note(icon: "lock.shield", text: "help_privacy")
                    }
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.vertical, Theme.Space.l)
            }
            .background(Theme.secondaryBackground)
            .navigationTitle(NSLocalizedString("help_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("settings_done", comment: "")) { dismiss() }
                }
            }
        }
        .tint(Theme.primary)
    }

    private func topic(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(NSLocalizedString(title, comment: ""))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(NSLocalizedString(body, comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.m)
    }

    private func note(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: icon)
                .foregroundStyle(Theme.primary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(NSLocalizedString(text, comment: ""))
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.m)
    }
}
