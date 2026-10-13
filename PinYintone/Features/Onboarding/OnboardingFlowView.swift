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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                BrandHeader()
                    .padding(.top, Theme.Space.xl)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(key: "onboarding_language_title")
                    LanguageChoiceList { languageChosen = true }
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 四种界面语言，各一行。每种语言用它自己的文字写名字——
/// 看不懂当前界面语言的人也认得出自己的那一行。
struct LanguageChoiceList: View {
    @ObservedObject private var localization = LocalizationManager.shared
    /// 是否标出当前语言（首次选择时不标：那时还没有「当前」可言）
    var marksCurrent = false
    let onChosen: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(LocalizationManager.supported, id: \.code) { lang in
                Button {
                    localization.setLanguage(lang.code)
                    onChosen()
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        Text(lang.label)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.Space.s)
                        Image(systemName: marksCurrent && localization.language == lang.code
                              ? "checkmark" : "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(marksCurrent && localization.language == lang.code
                                             ? Theme.accent : Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Theme.minTap)
                    .surfaceCard(padding: Theme.Space.m,
                                 highlighted: marksCurrent && localization.language == lang.code)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.language.\(lang.code)")
            }
        }
    }
}
