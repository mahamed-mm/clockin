import SwiftUI

@main
struct ClockinApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let services: AppServices

    init() {
        #if DEBUG
        DemoData.prepareFinishingSession()
        #endif
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
                    EndNotification.requestAuthorization()
                    services.engine.restore()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { services.engine.reconcile() }
        }
    }
}
