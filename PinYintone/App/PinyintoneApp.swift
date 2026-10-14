import Network
import SwiftUI
import UIKit

@main
struct PinyintoneApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        UITestSupport.applyLaunchOverrides()
        #endif
        // 启动即应用已保存的语言（重定向 Bundle.main）
        _ = LocalizationManager.shared
        // 读出本机账号，并把研究状态切到这个账号自己的那一份（未登录则为空）
        UserManager.shared.bootstrap()
        ConnectivityMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, CoreDataStack.shared.context)
                .onAppear { appState.sync(with: UserManager.shared.profile) }
                #if DEBUG
                .preferredColorScheme(UITestSupport.forcedColorScheme)
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // 会话编号：后台超过 30 分钟即轮换（字典 §7 的操作定义，非真实课次）
                ResearchSession.shared.willEnterForeground()
                ResearchCrashReporter.shared.start()
                AppSync.run()
            } else if phase == .background {
                ResearchSession.shared.didEnterBackground()
                AppSync.flushBeforeSuspend()
            }
        }
    }
}

/// 回到前台、恢复联网时做的同步。
@MainActor
enum AppSync {
    /// 退到后台时把还没传的研究记录再传一次。向系统要一小段后台时间，
    /// 传完或时间到就交还——练完直接锁屏的人，记录不该留在手机里等下次打开。
    static func flushBeforeSuspend() {
        let app = UIApplication.shared
        var token: UIBackgroundTaskIdentifier = .invalid
        token = app.beginBackgroundTask(withName: "research-flush") {
            if token != .invalid { app.endBackgroundTask(token); token = .invalid }
        }
        Task {
            await ResearchUploader.shared.flush()
            if token != .invalid { app.endBackgroundTask(token); token = .invalid }
        }
    }

    static func run() {
        // 登录时没送到后端的档案，这里补送（后台进行，不等它）
        UserManager.shared.syncRegistrationIfNeeded()
        Task {
            // 研究配置：决定「现在能不能参加研究」。取不到或不匹配时研究入口关闭，
            // 普通练习不受影响，学习者看不到任何配置层面的报错。
            await ResearchConfig.shared.refresh()
            // 业务记录与研究数据分开上报：研究链路有独立的同意校验，
            // 一方失败不应拖住另一方
            await SyncService.shared.syncAll()
            await ResearchUploader.shared.flush()
        }
    }
}

/// 网络恢复时补传。断网期间存下的问卷、尝试与事件不必等用户下次回前台。
/// Network 是系统框架，不引入第三方依赖。
final class ConnectivityMonitor {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = ConnectivityMonitor()

    private let monitor = NWPathMonitor()
    private var wasSatisfied = true
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                let monitor = ConnectivityMonitor.shared
                // 只在「从不通变成通」的那一下触发，不随每次路径变化重复跑
                if satisfied && !monitor.wasSatisfied { AppSync.run() }
                monitor.wasSatisfied = satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.pinyintone.connectivity"))
    }
}

#if DEBUG
/// 仅开发构建：界面自动化测试的启动开关。**正式构建里这段代码不存在。**
///
/// 由启动环境变量控制：
/// - `PT_UITEST_RESET=1`：清空本机全部状态（偏好、研究存储、练习记录），从全新安装开始
/// - `PT_UITEST_LANGUAGE=fr`：直接设定界面语言，跳过语言选择页
/// - `PT_UITEST_LOGIN=<标识>`：在登录页显示一个测试登录按钮（Sign in with Apple
///   无法在无人值守的模拟器里完成）
/// - `PT_API_BASE_URL`：把后端指到本地测试服务（见 APIClient）
/// - `PT_SYNTHETIC_AUDIO=match|silent`：用合成信号代替麦克风（见 RecordingSource）
/// - `PT_UITEST_APPEARANCE=dark|light`：固定外观，用来截深色界面
///   （无界面的模拟器上系统外观切换不生效）。不设则跟随系统。
///
/// 开发构建下纳入的参与者一律 is_test=true，正式导出默认排除。
enum UITestSupport {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static var loginIdentifier: String? { env["PT_UITEST_LOGIN"] }

    /// nil = 跟随系统（正常情况）
    static var forcedColorScheme: ColorScheme? {
        switch env["PT_UITEST_APPEARANCE"] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    static func applyLaunchOverrides() {
        if env["PT_UITEST_RESET"] == "1" { resetEverything() }
        if let language = env["PT_UITEST_LANGUAGE"] {
            UserDefaults.standard.set(language, forKey: LocalizationManager.storageKey)
            UserDefaults.standard.set(true, forKey: "pt_language_chosen")
        }
    }

    private static func resetEverything() {
        // 研究存储按账号分域，逐个清掉
        let prefs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: prefs.path)) ?? []
        for file in files where file.hasPrefix("pt.research.") {
            UserDefaults.standard.removePersistentDomain(
                forName: (file as NSString).deletingPathExtension)
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        LocalDataPurger.purgeAll()
    }
}
#endif
