import SwiftUI

@main
struct PinyintoneApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 启动即应用已保存的语言（重定向 Bundle.main）
        _ = LocalizationManager.shared
        UserManager.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, CoreDataStack.shared.context)
                .onAppear {
                    // 首次启动：确定 A/B 分组（安装时随机，不可更改）
                    appState.group = GroupAssignment.shared.group
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // 进入前台时同步未上传的本地记录（离线安全，失败下次重试）
            if phase == .active {
                Task { await SyncService.shared.syncAll() }
            }
        }
    }
}
