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
                    // A/B 分组由后端注册时分配，已存于 profile；从档案同步
                    appState.sync(with: UserManager.shared.profile)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // 进入前台时同步未上传的本地记录（离线安全，失败下次重试）
            if phase == .active {
                // 会话编号：后台超过 30 分钟即轮换（字典 §7 的操作定义，非真实课次）
                ResearchSession.shared.willEnterForeground()
                ResearchCrashReporter.shared.start()
                // 先用缓存窗口开门禁，再联网刷新：离线不应让已纳入的用户停止采集
                ResearchConfig.shared.applyCachedWindow()
                Task {
                    await ResearchConfig.shared.refresh()
                    await SyncService.shared.syncAll()
                    // 研究事件与业务记录分开上报：研究链路有独立的同意校验，
                    // 一方失败不应拖住另一方
                    await ResearchUploader.shared.flush()
                }
            } else if phase == .background {
                ResearchSession.shared.didEnterBackground()
            }
        }
    }
}
