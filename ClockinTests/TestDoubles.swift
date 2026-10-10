import Foundation
import UserNotifications
@testable import Clockin

@MainActor
final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class SpyLog: FocusLogging {
    struct Failure: Error {}

    var recorded: [CompletedFocus] = []
    /// While true every save fails, like a store that won't open.
    var failing = false

    func record(_ focus: CompletedFocus) throws {
        if failing { throw Failure() }
        guard !recorded.contains(where: { $0.id == focus.id }) else { return }
        recorded.append(focus)
    }
}

@MainActor
final class SpyEffects: SessionEffects {
    var events: [SessionEvent] = []
    func sessionEngine(_ engine: SessionEngine, didEmit event: SessionEvent) { events.append(event) }
}

@MainActor
final class SpyLiveActivity: LiveActivityControlling {
    var calls: [String] = []
    var lastBreakDuration: TimeInterval?
    var lastCompletedToday: Int?
    var enabled = true
    var flushes = 0

    func sync(with session: ActiveSession, completedToday: Int, breakDuration: TimeInterval) {
        calls.append("sync")
        lastBreakDuration = breakDuration
        lastCompletedToday = completedToday
    }
    func showFocusDone(completedToday: Int) {
        calls.append("done")
        lastCompletedToday = completedToday
    }
    func endAll() { calls.append("endAll") }
    func areActivitiesEnabled() async -> Bool { enabled }
    func flush() async { flushes += 1 }
}

@MainActor
final class SpyNotifier: EndNotifying {
    var calls: [String] = []
    var status: UNAuthorizationStatus = .authorized

    var flushes = 0

    func schedule(for session: ActiveSession) { calls.append("schedule") }
    func cancel() { calls.append("cancel") }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func flush() async { flushes += 1 }
}

@MainActor
final class SpyWidgets: WidgetReloading {
    var reloads = 0
    func reloadAll() { reloads += 1 }
}

@MainActor
final class SpyHaptics: CompletionFeedback {
    var plays = 0
    func play() { plays += 1 }
}

@MainActor
final class SpyAnnouncer {
    var spoken: [String] = []
}
