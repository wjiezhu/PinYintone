import SwiftUI

struct ContentView: View {
    @StateObject private var userManager = UserManager.shared

    var body: some View {
        Group {
            if userManager.profile == nil {
                OnboardingFlowView()
            } else {
                switch userManager.profile!.role {
                case .guest, .student:
                    StudentHomeView()
                case .teacher:
                    TeacherDashboardView()
                }
            }
        }
        .environmentObject(userManager)
    }
}
