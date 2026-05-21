import SwiftUI

/// 主页（对应论文图 1 三大模块入口）。
/// AppState 驱动：所有人可见送气/声调训练；教师模式额外显示教师控制台。
/// 保留游客绑定提示、班级码徽章、设置入口。
struct HomeView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showBindSheet = false
    @State private var showSettings = false
    @State private var showHelp = false

    private var profile: UserProfile? { userManager.profile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HeaderBannerView(nickname: profile?.nickname)

                    // 游客：引导绑定班级码；已绑定学生：显示班级码徽章
                    if profile?.role == .guest {
                        GuestBindCardView { showBindSheet = true }
                    } else if let code = profile?.classCode {
                        ClassCodeBadgeView(code: code)
                    }

                    // 送气训练（论文 3.3 蒲公英模块）
                    ModuleCard(
                        icon: "wind",
                        title: NSLocalizedString("stage1_title", comment: ""),
                        subtitle: NSLocalizedString("stage1_subtitle", comment: ""),
                        color: .teal
                    ) { AspirationView() }

                    // 声调训练（论文 3.2 A/B 实验）
                    ModuleCard(
                        icon: "waveform.and.mic",
                        title: NSLocalizedString("stage2_title", comment: ""),
                        subtitle: NSLocalizedString("stage2_subtitle", comment: ""),
                        color: .blue
                    ) { ToneTrainingView() }

                    // 自由文本练习（关卡 3，不参与 A/B）
                    ModuleCard(
                        icon: "text.bubble",
                        title: NSLocalizedString("stage3_title", comment: ""),
                        subtitle: NSLocalizedString("stage3_subtitle", comment: ""),
                        color: .purple
                    ) { FreeTextInputView() }

                    // 教师控制台（教师模式解锁，论文 3.4）
                    if appState.isTeacherMode {
                        ModuleCard(
                            icon: "chart.bar.xaxis",
                            title: NSLocalizedString("module_teacher_console", comment: ""),
                            subtitle: NSLocalizedString("module_teacher_console_sub", comment: ""),
                            color: .indigo
                        ) { TeacherDashboardView() }
                    }
                }
                .padding(sizeClass == .regular ? 32 : 20)
            }
            .navigationTitle("Pinyintone")
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            // 右下角浮动「i」使用说明
            .overlay(alignment: .bottomTrailing) {
                Button { showHelp = true } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(Circle().fill(.white).padding(6))
                        .shadow(radius: 4, y: 2)
                }
                .accessibilityLabel(NSLocalizedString("help_title", comment: ""))
                .padding(20)
            }
        }
        .sheet(isPresented: $showBindSheet) {
            BindClassCodeSheet().environmentObject(userManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(userManager)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
    }
}
