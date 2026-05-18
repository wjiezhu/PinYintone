import AVFoundation
import SwiftUI

/// 首次启动流程：麦克风权限申请 → 语言选择 → 角色选择
struct OnboardingFlowView: View {
    @AppStorage("pt_app_language") private var appLanguage: String = "fr"
    @State private var micGranted: Bool? = nil
    @State private var languageSelected = false

    private let languages: [(code: String, flag: String, label: String)] = [
        ("fr", "🇫🇷", "Français"),
        ("zh", "🇨🇳", "中文"),
        ("en", "🇬🇧", "English"),
        ("ar", "🇸🇦", "العربية"),
    ]

    var body: some View {
        NavigationStack {
            if micGranted == nil {
                micPermissionPage
            } else if !languageSelected {
                languageSelectionPage
            } else {
                RoleSelectView()
            }
        }
        .onAppear { checkExistingMicPermission() }
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
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
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
                        appLanguage = lang.code
                        withAnimation { languageSelected = true }
                    } label: {
                        VStack(spacing: 8) {
                            Text(lang.flag).font(.system(size: 40))
                            Text(lang.label).font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(appLanguage == lang.code ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(appLanguage == lang.code ? Color.accentColor : .clear, lineWidth: 2)
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
        let status: AVAudioSession.RecordPermission
        if #available(iOS 17, *) {
            status = AVAudioApplication.shared.recordPermission
        } else {
            status = AVAudioSession.sharedInstance().recordPermission
        }
        switch status {
        case .granted:  micGranted = true
        case .denied:   micGranted = false
        case .undetermined: break   // 停在权限申请页
        @unknown default: break
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
