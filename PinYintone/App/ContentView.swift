import SwiftUI

struct ContentView: View {
    @StateObject private var userManager = UserManager.shared
    @StateObject private var localization = LocalizationManager.shared
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if userManager.profile == nil {
                // 首次使用：选择界面语言 → 建立或恢复账号。之后直接进练习首页。
                OnboardingFlowView()
            } else {
                // 登录后就是练习首页。参加研究是首页和设置里的一个自愿入口，
                // 不是进入 App 之前必须完成的步骤。
                MainTabView()
            }
        }
        // 只保留一个淡入淡出；系统开了「减弱动态效果」时连它也不要
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                   value: userManager.profile == nil)
        .environmentObject(userManager)
        .tint(Theme.primary)
        // 同步教师状态到 AppState
        .onAppear { appState.sync(with: userManager.profile) }
        .onChange(of: userManager.profile?.role) { _, _ in
            appState.sync(with: userManager.profile)
        }
        // 语言切换：注入 locale + 布局方向（阿拉伯语 RTL），并以 token 强制刷新整树
        .environment(\.locale, localization.locale)
        .environment(\.layoutDirection, localization.layoutDirection)
        .id(localization.refreshToken)
    }
}
