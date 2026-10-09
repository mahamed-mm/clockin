import SwiftData
import SwiftUI
import WidgetKit

/// Wires the engine to its side effects: Live Activity, notifications,
/// widget reloads, and the completion haptic.
@MainActor
@Observable
final class AppServices: SessionEffects {
    static let shared = AppServices()

    let container: ModelContainer
    let engine: SessionEngine
    /// The most recent session event, stamped so repeats still trigger haptics.
    private(set) var lastEvent = EventStamp(event: nil, serial: 0)
    /// Bumped on each completed focus session; drives the sunburst.
    private(set) var celebrations = 0

    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private let completionHaptics = CompletionHaptics()

    private init() {
        do {
            container = try SharedStore.makeModelContainer()
        } catch {
            container = try! SharedStore.makeModelContainer(inMemory: true)
        }
        engine = SessionEngine(store: DefaultsSessionStateStore(),
                               log: SwiftDataFocusLog(container: container))
        engine.effects = self
        IntentBridge.togglePause = { [weak self] in self?.engine.togglePause() }
    }

    func sessionEngine(_ engine: SessionEngine, didEmit event: SessionEvent) {
        switch event {
        case .started, .resumed, .breakStarted, .restored:
            if let session = engine.active {
                liveActivity.sync(with: session, completedToday: completedToday)
                EndNotification.schedule(for: session)
            }
        case .paused:
            if let session = engine.active { liveActivity.sync(with: session, completedToday: completedToday) }
            EndNotification.cancel()
        case .cancelled, .breakSkipped:
            liveActivity.endAll()
            EndNotification.cancel()
        case .focusCompleted:
            liveActivity.showFocusDone(completedToday: completedToday)
            completionHaptics.play()
            celebrations += 1
        case .breakFinished:
            liveActivity.endAll()
        }
        lastEvent = EventStamp(event: event, serial: lastEvent.serial + 1)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Focus sessions saved today, for the session pills on the Lock Screen.
    private var completedToday: Int {
        TodayStats.fetchRecords(on: .now, calendar: .current, context: container.mainContext).count
    }

    #if DEBUG
    /// Replays an event's feedback without touching the session: its haptic,
    /// and for a completion the "ding" pattern and the sunburst.
    func debugReplay(_ event: SessionEvent) {
        if case .focusCompleted = event {
            completionHaptics.play()
            celebrations += 1
        }
        lastEvent = EventStamp(event: event, serial: lastEvent.serial + 1)
    }
    #endif
}

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
        case .focusCompleted, .restored, nil: nil
        }
    }
}
