import SwiftUI

/// 研究授权界面（需求 §2）。
///
/// 四条硬约束，改动前请先读：
/// - **与普通注册分开**：这不是注册流程的一步，用户可以完全跳过。
/// - **不默认勾选**：同意按钮在用户主动打开确认开关之前不可用。
/// - **不同意仍可用全部功能**：「暂不参与」直接进入 App，不降级、不再追问。
/// - **展示目的、采集内容、用途及退出方式**：四段说明缺一不可。
struct ResearchConsentView: View {
    /// 完成后回调：true = 已同意并纳入，false = 谢绝
    let onFinish: (Bool) -> Void

    @State private var hasReadAndAgreed = false
    @State private var isEnrolling = false
    @State private var enrollFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(NSLocalizedString("consent_title", comment: ""))
                    .font(.title2.bold())

                section("consent_purpose_title", "consent_purpose_body")
                section("consent_data_title", "consent_data_body")
                section("consent_use_title", "consent_use_body")
                section("consent_withdraw_title", "consent_withdraw_body")

                // 联系方式：字典 §16 要求知情说明中提供研究咨询/退出/删除渠道
                Text(NSLocalizedString("consent_contact", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                // 不默认勾选（需求 §2）
                Toggle(isOn: $hasReadAndAgreed) {
                    Text(NSLocalizedString("consent_checkbox", comment: ""))
                        .font(.callout)
                }

                if enrollFailed {
                    Text(NSLocalizedString("consent_enroll_failed", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                VStack(spacing: 10) {
                    Button {
                        Task { await agree() }
                    } label: {
                        if isEnrolling {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(NSLocalizedString("consent_agree", comment: ""))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasReadAndAgreed || isEnrolling)

                    // 谢绝：不降级、不再追问
                    Button(NSLocalizedString("consent_decline", comment: "")) {
                        ResearchConsent.shared.decline()
                        onFinish(false)
                    }
                    .disabled(isEnrolling)
                }
                .padding(.top, 4)

                Text(NSLocalizedString("consent_decline_hint", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func section(_ titleKey: String, _ bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(NSLocalizedString(titleKey, comment: ""))
                .font(.headline)
            Text(NSLocalizedString(bodyKey, comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func agree() async {
        isEnrolling = true
        enrollFailed = false
        defer { isEnrolling = false }

        let language = Locale.current.identifier
        // 先在端侧记同意，再联网纳入：字典 §5 要求首次同意**需联网确认后**
        // 才开启研究上传。纳入失败必须回滚本地同意状态，否则会出现
        // 「本地以为已同意、服务端没有参与者」的悬空状态，事件会攒在队列里发不出去。
        ResearchConsent.shared.grant(textVersion: ResearchConsent.textVersion,
                                     language: language)
        do {
            try await ResearchEnrollment.enrollCurrentUser(consentLanguage: language)
            onFinish(true)
        } catch {
            ResearchConsent.shared.withdraw()
            ResearchIdentity.shared.clearOnWithdrawal()
            enrollFailed = true
        }
    }
}
