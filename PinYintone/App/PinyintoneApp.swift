import SwiftUI

@main
struct PinyintoneApp: App {
    init() {
        UserManager.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
