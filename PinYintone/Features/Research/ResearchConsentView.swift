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
    @State private var enrollFailed = false   // 保留：联调阶段用于显示纳入失败

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

    /// 同意**只记本地状态，不立刻纳入**。
    ///
    /// 纳入要等背景表答完：字典 §4 要求参与者首次写入必须 `eligible`，
    /// 而资格由 B01–B05 的答案在**端侧**判定（字典 §10：
    /// 「背景筛选先在本地完成，符合条件后才上传背景实例」）。
    /// 此刻就 enroll 会写出一个资格未知的参与者。
    private func agree() async {
        let language = Locale.current.identifier
        ResearchConsent.shared.grant(textVersion: ResearchConsent.textVersion,
                                     language: language)
        onFinish(true)
    }
}
