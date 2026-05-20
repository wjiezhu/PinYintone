import SwiftUI

@main
struct PinyintoneApp: App {
    init() {
        // 启动即应用已保存的语言（重定向 Bundle.main）
        _ = LocalizationManager.shared
        UserManager.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, CoreDataStack.shared.context)
        }
    }
}
