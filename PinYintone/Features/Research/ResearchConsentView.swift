import SwiftUI

/// 知情说明（需求 U06 / R02）。
///
/// 硬约束，改动前请先读：
/// - **与普通注册分开**：这不是注册流程的一步，登录了也不等于同意研究。
/// - **不默认勾选**：同意按钮在用户主动打开确认开关之前不可用。
/// - **参与与暂不参加都看得见**，不参加仍可使用全部功能，不降级。
/// - **展示目的、采集内容、用途及退出方式**，并显示用户实际看到的文本版本。
struct ResearchConsentView: View {
    /// true = 同意（进入背景表）；false = 暂不参加
    let onFinish: (Bool) -> Void

    @State private var hasReadAndAgreed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                section("consent_purpose_title", "consent_purpose_body")
                section("consent_data_title", "consent_data_body")
                section("consent_use_title", "consent_use_body")
                section("consent_withdraw_title", "consent_withdraw_body")

                Text(NSLocalizedString("consent_contact", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 用户实际看到的是哪一版说明。尚未审定的稿子如实标出来。
                Text(String(format: NSLocalizedString("consent_version_line", comment: ""),
                            ResearchConsent.textVersion))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if ResearchConsent.textVersion.contains("unpublished") {
                    StatusLabel(kind: .warning,
                                text: NSLocalizedString("consent_draft_notice", comment: ""))
                        .font(.footnote)
                }

                Divider()

                // 不默认勾选
                Toggle(isOn: $hasReadAndAgreed) {
                    Text(NSLocalizedString("consent_checkbox", comment: ""))
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.accent)
                .accessibilityIdentifier("consent.toggle")

                Text(NSLocalizedString("consent_decline_hint", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Theme.Space.s) {
                Button {
                    ResearchConsent.grant()
                    onFinish(true)
                } label: {
                    Text(NSLocalizedString("consent_agree", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasReadAndAgreed)
                .accessibilityIdentifier("consent.agree")

                Button {
                    ResearchConsent.decline()
                    onFinish(false)
                } label: {
                    Text(NSLocalizedString("consent_decline", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("consent.decline")
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.m)
            .background(.bar)
        }
        .navigationTitle(NSLocalizedString("consent_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ titleKey: String, _ bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(NSLocalizedString(titleKey, comment: ""))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(NSLocalizedString(bodyKey, comment: ""))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
