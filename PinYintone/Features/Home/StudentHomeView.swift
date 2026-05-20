import SwiftUI

/// 学生/游客主页：问候横幅 + 三关卡入口 + 游客绑定提示
struct StudentHomeView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var showBindSheet = false
    @State private var showSettings = false

    private var profile: UserProfile? { userManager.profile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── 顶部问候横幅 ──────────────────────
                    HeaderBannerView(nickname: profile?.nickname)

                    // 游客状态：引导绑定班级码
                    if profile?.role == .guest {
                        GuestBindCardView { showBindSheet = true }
                    } else if let code = profile?.classCode {
                        // 已绑定学生：显示班级码徽章
                        ClassCodeBadgeView(code: code)
                    }

                    // ── 三关卡 ────────────────────────────
                    VStack(spacing: 12) {
                        StageCardView(
                            index: 1,
                            icon: "wind",
                            title: NSLocalizedString("stage1_title", comment: ""),
                            subtitle: NSLocalizedString("stage1_subtitle", comment: ""),
                            color: .teal,
                            destination: AnyView(AspirationView())
                        )
                        StageCardView(
                            index: 2,
                            icon: "waveform.and.mic",
                            title: NSLocalizedString("stage2_title", comment: ""),
                            subtitle: NSLocalizedString("stage2_subtitle", comment: ""),
                            color: .blue,
                            destination: AnyView(ToneTrainingView())
                        )
                        StageCardView(
                            index: 3,
                            icon: "text.bubble",
                            title: NSLocalizedString("stage3_title", comment: ""),
                            subtitle: NSLocalizedString("stage3_subtitle", comment: ""),
                            color: .purple,
                            destination: AnyView(FreeTextInputView())
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("Pinyintone")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showBindSheet) {
            BindClassCodeSheet()
                .environmentObject(userManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(userManager)
        }
    }
}
