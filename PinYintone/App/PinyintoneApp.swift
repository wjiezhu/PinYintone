import SwiftUI

@main
struct PinyintoneApp: App {
    @StateObject private var appState = AppState()

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
    }
}
