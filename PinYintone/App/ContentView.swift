import SwiftUI

struct ContentView: View {
    @StateObject private var userManager = UserManager.shared

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
