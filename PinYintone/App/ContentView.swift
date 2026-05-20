import SwiftUI

struct ContentView: View {
    @StateObject private var userManager = UserManager.shared
    @StateObject private var localization = LocalizationManager.shared
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            if userManager.profile == nil {
                OnboardingFlowView()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                // AppState 架构：统一主页，教师模式由 appState.isTeacherMode 解锁控制台
                HomeView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: userManager.profile == nil)
        .environmentObject(userManager)
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
