import SwiftUI
import UserNotifications

@main
struct ClockinApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let services: AppServices

    init() {
        #if DEBUG
        DemoData.prepareFinishingSession()
        #endif
        // Before launch finishes, so the end sound also plays while the app is open.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        services = AppServices.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .environment(services.engine)
                .modelContainer(services.container)
                .task {
                    #if DEBUG
                    DemoData.seedIfRequested(into: services.container.mainContext)
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
