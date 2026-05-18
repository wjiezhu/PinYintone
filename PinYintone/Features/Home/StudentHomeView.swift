import SwiftUI

/// 学生/游客主页：三关卡入口 + 游客绑定提示
struct StudentHomeView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var showBindSheet = false

    private var profile: UserProfile? { userManager.profile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 班级码徽章（学生已绑定时显示）
                    if let code = profile?.classCode {
                        ClassCodeBadgeView(code: code)
                    }

                    // 游客提示卡
                    if profile?.role == .guest {
                        GuestBindCardView { showBindSheet = true }
                    }

                    // 三关卡
                    VStack(spacing: 12) {
                        StageCardView(
                            index: 1,
                            icon: "wind",
                            title: NSLocalizedString("stage1_title", comment: ""),
                            subtitle: NSLocalizedString("stage1_subtitle", comment: ""),
                            color: .blue,
                            destination: AnyView(AspirationView())
                        )
                        StageCardView(
                            index: 2,
                            icon: "waveform.path.ecg",
                            title: NSLocalizedString("stage2_title", comment: ""),
                            subtitle: NSLocalizedString("stage2_subtitle", comment: ""),
                            color: .purple,
                            destination: AnyView(ToneTrainingView())
                        )
                        StageCardView(
                            index: 3,
                            icon: "text.bubble",
                            title: NSLocalizedString("stage3_title", comment: ""),
                            subtitle: NSLocalizedString("stage3_subtitle", comment: ""),
                            color: .green,
                            destination: AnyView(FreeTextInputView())
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle(greetingTitle)
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showBindSheet) {
            BindClassCodeSheet()
                .environmentObject(userManager)
        }
    }

    private var greetingTitle: String {
        if let name = profile?.nickname, !name.isEmpty {
            return String(format: NSLocalizedString("home_greeting_name", comment: ""), name)
        }
        return NSLocalizedString("home_greeting", comment: "")
    }
}
