import SwiftUI

struct ContentView: View {
    @StateObject private var userManager = UserManager.shared
    @StateObject private var localization = LocalizationManager.shared

    var body: some View {
        ZStack {
            if userManager.profile == nil {
                OnboardingFlowView()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                destinationView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: userManager.profile == nil)
        .environmentObject(userManager)
        // 语言切换：注入 locale + 布局方向（阿拉伯语 RTL），并以 token 强制刷新整树
        .environment(\.locale, localization.locale)
        .environment(\.layoutDirection, localization.layoutDirection)
        .id(localization.refreshToken)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch userManager.profile!.role {
        case .guest, .student:
            StudentHomeView()
        case .teacher:
            TeacherDashboardView()
        }
    }
}
