import Foundation
import Testing
import UIKit
@testable import Clockin

/// The Home Screen icon's quick actions.
@MainActor
struct QuickActionsTests {
    @Test func idleOffersTheLastTwoNamesAndHistory() {
        #expect(QuickAction.available(focusing: false, recentNames: []) == [.history])
        #expect(QuickAction.available(focusing: false, recentNames: ["Essay"]) == [.start(name: "Essay"), .history])
        #expect(QuickAction.available(focusing: false, recentNames: ["Essay", "Piano", "Spanish"])
                == [.start(name: "Essay"), .start(name: "Piano"), .history])
    }

    @Test func focusOffersPauseParkAndHistory() {
        #expect(QuickAction.available(focusing: true, recentNames: ["Essay"]) == [.pause, .park, .history])
    }

    @Test func itemsRoundTripWithTheirSymbols() throws {
        for action: QuickAction in [.start(name: "Essay"), .pause, .park, .history] {
            let item = action.shortcutItem { _ in "pencil" }
            #expect(QuickAction(item) == action)
            #expect(!item.localizedTitle.isEmpty)
        }
        #expect(QuickAction.start(name: "Essay").shortcutItem { _ in "pencil" }.localizedTitle.contains("Essay"))
        #expect(QuickAction(type: "com.example.other", userInfo: nil) == nil)
    }

    @Test func performingThemDoesWhatTheySay() {
        let clock = FakeClock()
        let services = AppServices(container: AppServices.makeEmptyContainer(),
                                   stateStore: InMemorySessionStateStore(), now: { [clock] in clock.now },
                                   calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: SpyLiveActivity(), notifications: SpyNotifier(),
                                   widgets: SpyWidgets(), haptics: SpyHaptics(), announce: { _ in })
        services.perform(.park)
        #expect(!services.parkFieldOpen, "nothing to park in")
        services.perform(.start(name: "Essay"))
        #expect(services.engine.active?.name == "Essay")
        services.perform(.park)
        #expect(services.parkFieldOpen)
        services.perform(.pause)
        #expect(services.engine.active?.isPaused == true)
        services.perform(.start(name: "Piano"))
        #expect(services.engine.active?.name == "Essay", "never replaces a session")
    }
}
