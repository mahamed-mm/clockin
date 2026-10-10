import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

/// Reloads widget timelines. A seam so tests don't touch WidgetCenter.
@MainActor
protocol WidgetReloading {
    func reloadAll()
}

struct SystemWidgets: WidgetReloading {
    func reloadAll() { WidgetCenter.shared.reloadAllTimelines() }
}

/// The focus-complete haptic.
@MainActor
protocol CompletionFeedback {
    func play()
}

extension CompletionHaptics: CompletionFeedback {}

/// Whether the end-of-phase alert and the Live Activity can reach the user.
enum AlertStatus: Equatable, Sendable {
    /// Not checked yet.
    case unknown
    /// Notifications haven't been asked for yet; that happens on the first Start.
    case notAsked
    case ready
    case notificationsOff
    case liveActivitiesOff
}

/// Wires the engine to its side effects: Live Activity, notifications,
/// widget reloads, the completion haptic, and VoiceOver announcements.
@MainActor
@Observable
final class AppServices: SessionEffects {
    static let shared = AppServices.live()

    let container: ModelContainer
    let engine: SessionEngine
    /// True when the history store couldn't be opened. Timers still work, and
    /// finished sessions wait in the session state until it opens again.
    let historyUnavailable: Bool
    /// The most recent session event, stamped so repeats still trigger haptics.
    private(set) var lastEvent = EventStamp(event: nil, serial: 0)
    /// Bumped on each completed focus session; drives the sunburst.
    private(set) var celebrations = 0
    private(set) var alertStatus: AlertStatus = .unknown

    @ObservationIgnored private let liveActivity: LiveActivityControlling
    @ObservationIgnored private let notifications: EndNotifying
    @ObservationIgnored private let widgets: WidgetReloading
    @ObservationIgnored private let haptics: CompletionFeedback
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    init(container: ModelContainer,
         historyUnavailable: Bool = false,
         stateStore: SessionStateStoring,
         now: @escaping () -> Date = Date.init,
         schedulesCompletion: Bool = true,
         liveActivity: LiveActivityControlling,
         notifications: EndNotifying,
         widgets: WidgetReloading,
         haptics: CompletionFeedback,
         announce: @escaping @MainActor (String) -> Void) {
        self.container = container
        self.historyUnavailable = historyUnavailable
        self.liveActivity = liveActivity
        self.notifications = notifications
        self.widgets = widgets
        self.haptics = haptics
        self.announce = announce
        let log: FocusLogging = historyUnavailable ? UnavailableFocusLog() : SwiftDataFocusLog(container: container)
        engine = SessionEngine(now: now, store: stateStore, log: log, schedulesCompletion: schedulesCompletion)
        engine.effects = self
    }

    /// The real thing: the App Group store, ActivityKit, notifications, haptics.
    static func live() -> AppServices {
        var historyUnavailable = false
        let container: ModelContainer
        do {
            container = try SharedStore.makeModelContainer()
        } catch {
            Log.store.fault("Couldn't open the history store; History is unavailable this launch: \(error, privacy: .public)")
            historyUnavailable = true
            container = makeEmptyContainer()
        }
        let services = AppServices(container: container, historyUnavailable: historyUnavailable,
                                   stateStore: DefaultsSessionStateStore(),
                                   liveActivity: LiveActivityController(), notifications: EndNotifier(),
                                   widgets: SystemWidgets(), haptics: CompletionHaptics(),
                                   announce: { AccessibilityNotification.Announcement($0).post() })
        IntentBridge.togglePause = { [weak services] in
            services?.engine.togglePause()
            await services?.settle()
        }
        return services
    }

    /// An empty in-memory store, for the UI when the real one won't open, and for previews.
    static func makeEmptyContainer() -> ModelContainer {
        do {
            return try SharedStore.makeModelContainer(inMemory: true)
        } catch {
            fatalError("An in-memory store only fails if the model itself is broken: \(error)")
        }
    }

    // MARK: Effects

    func sessionEngine(_ engine: SessionEngine, didEmit event: SessionEvent) {
        switch event {
        case .started, .resumed, .breakStarted, .restored:
            if let session = engine.active {
                liveActivity.sync(with: session, completedToday: completedToday,
                                  breakDuration: Durations.duration(for: .rest))
                notifications.schedule(for: session)
            }
        case .paused:
            if let session = engine.active {
                liveActivity.sync(with: session, completedToday: completedToday,
                                  breakDuration: Durations.duration(for: .rest))
            }
            notifications.cancel()
        case .cancelled, .breakSkipped, .completionDismissed:
            liveActivity.endAll()
            notifications.cancel()
        case .focusCompleted(let live):
            liveActivity.showFocusDone(completedToday: completedToday)
            haptics.play()
            celebrations += 1
            if live { announce("Focus complete. Time for a break.") }
        case .breakFinished(let live):
            liveActivity.endAll()
            if live { announce("Break's over. Ready when you are.") }
        case .historySaved:
            break // The widget reload below picks up the newly saved sessions.
        }
        lastEvent = EventStamp(event: event, serial: lastEvent.serial + 1)
        widgets.reloadAll()
    }

    /// Restores the engine at launch, then clears anything it no longer explains.
    func restore() {
        engine.restore()
        endOrphanedActivities()
    }

    /// Catches up after returning to the foreground.
    func reconcile() {
        engine.reconcile()
        endOrphanedActivities()
    }

    /// When idle nothing should be on the Lock Screen or in the Dynamic Island,
    /// e.g. a card left by a session that ended while the app wasn't running.
    /// `endAll` lists activities off the main actor, so this is cheap when there are none.
    private func endOrphanedActivities() {
        if engine.stage == .idle { liveActivity.endAll() }
    }

    /// Waits for side effects still in flight: the end alert and Live Activity
    /// updates. Intents that run while the app is in the background await this
    /// so the system doesn't suspend the app before they land.
    func settle() async {
        await notifications.flush()
        await liveActivity.flush()
    }

    /// Re-reads whether alerts and Live Activities are allowed. Called at launch
    /// and on every return to the foreground, which covers coming back from the
    /// permission prompt or from Settings.
    func refreshAlertStatus() async {
        let notificationStatus = await notifications.authorizationStatus()
        let activitiesEnabled = await liveActivity.areActivitiesEnabled()
        alertStatus = switch notificationStatus {
        case .notDetermined: .notAsked
        case .denied: .notificationsOff
        default: activitiesEnabled ? .ready : .liveActivitiesOff
        }
    }

    /// Focus sessions finished today, saved or waiting, for the pills on the Lock Screen.
    private var completedToday: Int {
        let today = engine.now()
        let saved = TodayStats.fetchRecords(on: today, calendar: .current, context: container.mainContext)
        return TodayStats.rows(saved: saved.map(\.row), pending: engine.pendingRecords(on: today)).count
    }

    #if DEBUG
    /// In memory and without side effects, so previews never touch real data.
    static let preview = AppServices(container: makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                     liveActivity: SilentEffects(), notifications: SilentEffects(),
                                     widgets: SilentEffects(), haptics: SilentEffects(), announce: { _ in })

    /// Replays an event's feedback without touching the session: its haptic,
    /// and for a completion the "ding" pattern and the sunburst.
    func debugReplay(_ event: SessionEvent) {
        if case .focusCompleted = event {
            haptics.play()
            celebrations += 1
        }
        lastEvent = EventStamp(event: event, serial: lastEvent.serial + 1)
    }
    #endif
}

#if DEBUG
/// Does nothing, for previews.
@MainActor
private final class SilentEffects: LiveActivityControlling, EndNotifying, WidgetReloading, CompletionFeedback {
    func sync(with session: ActiveSession, completedToday: Int, breakDuration: TimeInterval) {}
    func showFocusDone(completedToday: Int) {}
    func endAll() {}
    func areActivitiesEnabled() async -> Bool { true }
    func flush() async {}
    func schedule(for session: ActiveSession) {}
    func cancel() {}
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func reloadAll() {}
    func play() {}
}
#endif

struct EventStamp: Equatable {
    var event: SessionEvent?
    var serial: Int

    /// Light-touch feedback for each transition. Focus completion uses the
    /// custom Core Haptics pattern instead.
    var feedback: SensoryFeedback? {
        switch event {
        case .started: .impact(weight: .medium, intensity: 0.8)
        case .paused, .resumed: .selection
        case .cancelled: .warning
        case .breakStarted: .impact(flexibility: .soft, intensity: 0.7)
        case .breakSkipped: .impact(weight: .light)
        case .breakFinished: .success
        case .focusCompleted, .completionDismissed, .restored, .historySaved, nil: nil
        }
    }
}
