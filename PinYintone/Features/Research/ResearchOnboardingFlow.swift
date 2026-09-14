import SwiftUI

/// 研究相关的首次使用流程：授权 → 背景表 → 判资格 → 纳入。
///
/// 顺序不可调换，每一步都有出处：
/// - 授权在最前：填背景表**不等于**研究同意（字典 §1 明确禁止这样解读）。
/// - 背景表在纳入之前：资格由 B01–B05 在端侧判定，而参与者首次写入
///   必须是 `eligible`（字典 §4、§10）。
/// - 纳入在最后：只有同意且合格者才写入研究库；
///   其余用户**照常使用全部功能**，研究库里不产生任何记录。
struct ResearchOnboardingFlow: View {
    let onFinish: () -> Void

    private enum Step { case consent, background, enrolling, done }
    @State private var step: Step = .consent
    @State private var enrollFailed = false

    var body: some View {
        Group {
            switch step {
            case .consent:
                ResearchConsentView { agreed in
                    // 谢绝：不再追问，直接进 App，不降级
                    step = agreed ? .background : .done
                    if !agreed { onFinish() }
                }
            case .background:
                SurveyFormView(formKey: "background_v1") { outcome in
                    Task { await handleBackground(outcome) }
                }
            case .enrolling:
                VStack(spacing: 14) {
                    ProgressView()
                    if enrollFailed {
                        Text(NSLocalizedString("consent_enroll_failed", comment: ""))
                            .font(.footnote).foregroundStyle(.orange)
                        Button(NSLocalizedString("consent_decline", comment: "")) {
                            step = .done; onFinish()
                        }
                    }
                }
            case .done:
                Color.clear.onAppear { onFinish() }
            }
        }
    }

    private func handleBackground(_ outcome: SurveyOutcome) async {
        // 端侧判资格。跳过或拒答背景表 → 资格未知 → 不纳入，
        // **不猜测缺失背景**（字典 §4：exclusion_reason 不自动猜测）。
        let eligibility = ResearchEligibility.evaluate(
            isAdult: outcome.isAdult,
            nationalities: outcome.nationalities,
            courseStage: outcome.courseStage,
            consentGranted: ResearchConsent.shared.allowsResearchCollection,
            priorUse: .init(status: .unknown, evidence: .insufficient))
        ResearchEventLog.shared.eligibility = eligibility

        guard eligibility == .eligible else {
            // 不合格者正常使用 App，研究库不产生记录
            step = .done
            onFinish()
            return
        }

        step = .enrolling
        do {
            try await ResearchEnrollment.enrollCurrentUser(
                consentLanguage: Locale.current.identifier)
            // 纳入成功后才上传背景答案（字典 §10：符合条件后才上传背景实例）
            await SurveyUploader.shared.upload(outcome)
            step = .done
            onFinish()
        } catch {
            // 纳入失败：回滚本地同意，避免「本地以为已参与、服务端没有参与者」
            // 的悬空状态——那会让事件攒在队列里永远发不出去
            ResearchConsent.shared.withdraw()
            ResearchIdentity.shared.clearOnWithdrawal()
            ResearchEventLog.shared.clearPendingOnWithdrawal()
            enrollFailed = true
        }
    }
}
