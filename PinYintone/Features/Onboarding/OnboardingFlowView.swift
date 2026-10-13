import SwiftUI

/// 首次使用流程（需求 R02）：**选择界面语言 → 建立或恢复账号**，然后直接进练习首页。
///
/// 这里刻意不做两件事：
/// - **不在这里申请麦克风权限**。权限在首次实际录音前申请，那时用户已经选好语言，
///   用途说明能用他看得懂的语言呈现；拒绝了也只是暂时不能录音，照样能浏览。
/// - **不在这里邀请参加研究**。研究邀请原本排在登录之前，纳入接口拿到的是空账号。
///   现在先有账号、先能练习；参加研究是登录之后首页和设置里的一个自愿入口。
///
/// 退出登录后再进来：语言已选，直接到账号这一步。
struct OnboardingFlowView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @AppStorage("pt_language_chosen") private var languageChosen = false

    var body: some View {
        NavigationStack {
            if !languageChosen {
                languageSelectionPage
            } else {
                RoleSelectView()
            }
        }
        .tint(Theme.accent)
    }

    private var languageSelectionPage: some View {
        List {
            Section {
                ForEach(LocalizationManager.supported, id: \.code) { lang in
                    Button {
                        localization.setLanguage(lang.code)
                        languageChosen = true
                    } label: {
                        HStack {
                            Text(lang.label)
                                .font(.title3)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Theme.minTap)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("onboarding.language.\(lang.code)")
                }
            } header: {
                Text(NSLocalizedString("onboarding_language_title", comment: ""))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Pinyintone")
        .navigationBarTitleDisplayMode(.large)
    }
}
