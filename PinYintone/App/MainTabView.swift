import SwiftUI

/// 主导航（需求 U02）：三项原生底部导航——练习、记录、设置。
///
/// 首次打开停在「练习」。记录是一级入口，不再埋在设置里。
/// 学生的导航里**没有**班级码或教师工作区；教师账号多一个「教师」页签
/// （既有功能原样保留，不扩建）。
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: Tab = .practice

    enum Tab: Hashable { case practice, history, settings, teacher }

    var body: some View {
        TabView(selection: $selection) {
            PracticeHomeView()
                .tabItem {
                    Label(NSLocalizedString("tab_practice", comment: ""), systemImage: "mic")
                }
                .tag(Tab.practice)

            NavigationStack {
                LearningHistoryView()
            }
            .tabItem {
                Label(NSLocalizedString("tab_history", comment: ""),
                      systemImage: "list.bullet.rectangle")
            }
            .tag(Tab.history)

            if appState.isTeacherMode {
                TeacherDashboardView()     // 自带 NavigationStack
                .tabItem {
                    Label(NSLocalizedString("tab_teacher", comment: ""),
                          systemImage: "person.2")
                }
                .tag(Tab.teacher)
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(NSLocalizedString("tab_settings", comment: ""), systemImage: "gearshape")
            }
            .tag(Tab.settings)
        }
        .tint(Theme.accent)
    }
}
