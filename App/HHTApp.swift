import SwiftUI
import HHTCore
#if os(iOS)
import UIKit
import BackgroundTasks
#endif

@main
struct HHTApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
    init() { Toon.configureAppearance() }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear { model.launch() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.collector.startMotionUpdatesIfAuthorized()   // e.g. Motion & Fitness enabled in Settings
                Task { await model.runInference() }
            }
        }
    }
}

#if os(iOS)
/// Handles launches without UI: iOS relaunches the app in the background for region exits, visits and
/// significant location changes after it was terminated. Collection must restart here.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTaskID = "com.zyang91.hht.refresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            Task { @MainActor in
                await AppModel.shared.runInference()
                AppModel.shared.autoBackupIfDue()
                task.setTaskCompleted(success: true)
                AppDelegate.scheduleRefresh()
            }
        }
        MainActor.assumeIsolated { AppModel.shared.launch() }
        Self.scheduleRefresh()
        return true
    }

    static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date().addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
}
#endif
