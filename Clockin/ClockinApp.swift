import SwiftUI
import UserNotifications

@main
struct ClockinApp: App {
    /// Only for the orientations bedside mode allows.
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let services: AppServices

    init() {
        #if DEBUG
        DemoClock.prepare()
        DemoData.prepareFinishingSession()
        if ProcessInfo.processInfo.arguments.contains("-ResetOnboarding") { Onboarding.reset() }
        #endif
        // Before launch finishes, so the end sound also plays while the app is open.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        services = AppServices.shared
        ClockinTips.configure()
        #if DEBUG
        DemoData.applyDemoSettings(to: services)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Settings › Appearance; nil follows the phone.
                .preferredColorScheme(services.settings.appearance.colorScheme)
                .environment(services)
                .environment(services.engine)
                .modelContainer(services.container)
                .task {
                    #if DEBUG
                    DemoData.seedIfRequested(into: services)
                    #endif
                    services.restore()
                    await services.refreshAlertStatus()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            services.reconcile()
            Task { await services.refreshAlertStatus() }
        }
    }
}

extension Appearance {
    /// What SwiftUI should force, or nil to follow the phone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
