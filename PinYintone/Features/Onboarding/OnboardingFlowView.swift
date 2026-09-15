import AVFoundation
import SwiftUI
import UIKit

/// 首次启动流程：麦克风权限申请（含数据用途说明）→ 语言选择 → 角色选择
/// 退出登录后再次进入：麦克风已授权、语言已选择，直接进入角色选择
///
/// 权限被拒时（升级需求 §4.1）不再默默放行，而是给出**可执行的系统设置入口**，
/// 并允许"暂不开启，先浏览"——不把学习者锁死在权限页。
struct OnboardingFlowView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pt_language_chosen") private var languageChosen = false
    /// 研究邀请是否已展示过。**只邀请一次**——谢绝后不再打扰（需求 §2）。
    @AppStorage("pt_research_invited") private var researchInvited = false
    @State private var micGranted: Bool? = nil
    /// 学习者选择了"暂不开启"，跳过被拒页继续浏览
    @State private var micSkipped = false

    /// 是否展示研究邀请。
    ///
    /// 三个条件缺一不可：
    /// - 还没邀请过（谢绝或完成后都不再展示）
    /// - 服务端有生效的采集配置——没有就不邀请，也**不猜**一个配置
    /// - 当前不在已同意状态（重装后本地状态已清，由服务端幂等返回原编号）
    private var shouldInviteToResearch: Bool {
        !researchInvited
            && ResearchConfig.shared.manifestID != nil
            && ResearchConsent.shared.state == .notAsked
    }

    private var languages: [(code: String, flag: String, label: String)] {
        LocalizationManager.supported
    }

    var body: some View {
        NavigationStack {
            if micGranted == nil {
                micPermissionPage
            } else if micGranted == false && !micSkipped {
                micDeniedPage
            } else if !languageChosen {
                languageSelectionPage
            } else if shouldInviteToResearch {
                // 研究邀请在语言选好之后：知情说明必须以用户看得懂的语言呈现。
                // 放在首次练习之前（需求 §3：前置问卷保持首次练习前的时间定位）。
                ResearchOnboardingFlow { researchInvited = true }
            } else {
                RoleSelectView()
            }
        }
        .onAppear { checkExistingMicPermission() }
        // 从系统设置返回时重新读取授权状态，无需重启 App
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkExistingMicPermission() }
        }
    }

    // MARK: - Mic permission page

    private var micPermissionPage: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(NSLocalizedString("welcome_title", comment: ""))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("onboarding_mic_body", comment: ""))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            // 录音处理方式 / 是否上传原始音频 / 数据用途（升级需求 §4.1）
            Text(NSLocalizedString("onboarding_mic_privacy", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                requestMicPermission()
            } label: {
                Text(NSLocalizedString("onboarding_mic_allow", comment: ""))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityIdentifier("onboarding.allowMic")
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Mic denied page

    /// 权限被拒：给出可执行的系统设置入口，而不是一句"需要麦克风"了事
    private var micDeniedPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text(NSLocalizedString("onboarding_mic_denied_title", comment: ""))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(NSLocalizedString("onboarding_mic_denied_body", comment: ""))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    openSystemSettings()
                } label: {
                    Text(NSLocalizedString("onboarding_open_settings", comment: ""))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("onboarding.openSettings")

                Button(NSLocalizedString("onboarding_mic_recheck", comment: "")) {
                    checkExistingMicPermission()
                }
                .font(.subheadline)

                Button(NSLocalizedString("onboarding_mic_skip", comment: "")) {
                    micSkipped = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    /// 跳到本 App 的系统设置页（麦克风开关就在那一页）
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Language selection page

    private var languageSelectionPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(NSLocalizedString("onboarding_language_title", comment: ""))
                .font(.title.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(languages, id: \.code) { lang in
                    Button {
                        localization.setLanguage(lang.code)
                        withAnimation { languageChosen = true }
                    } label: {
                        VStack(spacing: 8) {
                            Text(lang.flag).font(.system(size: 40))
                            Text(lang.label).font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(localization.language == lang.code ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(localization.language == lang.code ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Helpers

    /// 检查是否已授权（重启 app 时跳过权限页）
    private func checkExistingMicPermission() {
        // iOS 17+ 与旧版返回类型不同，分别处理
        if #available(iOS 17, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:      micGranted = true
            case .denied:       micGranted = false
            case .undetermined: break   // 停在权限申请页
            @unknown default:   break
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:      micGranted = true
            case .denied:       micGranted = false
            case .undetermined: break
            @unknown default:   break
            }
        }
    }

    private func requestMicPermission() {
        if #available(iOS 17, *) {
            Task {
                let granted = await AVAudioApplication.requestRecordPermission()
                await MainActor.run { micGranted = granted }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { micGranted = granted }
            }
        }
    }
}
