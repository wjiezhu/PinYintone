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
    /// 打开时定下要显示的那一版；读的过程中配置刷新也不换——同意的必须是看到的那一版
    @State private var text = ResearchConsent.current
    @State private var showFullText = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(NSLocalizedString("consent_summary", comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                section("consent_benefit_title", "consent_benefit_body")

                Button {
                    showFullText = true
                } label: {
                    Label(NSLocalizedString("consent_read_full", comment: ""),
                          systemImage: "doc.text")
                }
                .accessibilityIdentifier("consent.readFull")

                // 用户实际看到的是哪一版说明。尚未审定的稿子如实标出来。
                Text(String(format: NSLocalizedString("consent_version_line", comment: ""),
                            text.rawValue))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("consent.version")
                // 测试配置下发的是未审定的稿子：如实标出来
                if ResearchConfig.shared.available?.isTest == true {
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
                .tint(Theme.primary)
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
                    ResearchConsent.grant(text)
                    onFinish(true)
                } label: {
                    Text(NSLocalizedString("consent_agree", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!hasReadAndAgreed)
                .accessibilityIdentifier("consent.agree")

                Button {
                    ResearchConsent.decline()
                    onFinish(false)
                } label: {
                    Text(NSLocalizedString("consent_decline", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("consent.decline")
            }
            .bottomBarSurface()
        }
        .navigationTitle(NSLocalizedString("consent_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFullText) { fullText }
    }

    /// 同意书全文。放在 App 内，保证看到的就是同意记录里写的那一版
    private var fullText: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    ForEach(text.sections, id: \.body) { item in
                        section(item.title, item.body)
                    }
                    Text(NSLocalizedString("consent_contact", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
            .navigationTitle(NSLocalizedString("consent_full_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common_close", comment: "")) { showFullText = false }
                        .accessibilityIdentifier("consent.fullClose")
                }
            }
        }
        .tint(Theme.primary)
        .accessibilityIdentifier("consent.fullText")
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
