import Foundation
import UserNotifications
@testable import Clockin

@MainActor
final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Fixed so day boundaries in tests don't depend on the machine's time zone.
let osloCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
    return calendar
}()

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

    func update(_ focus: CompletedFocus) throws {
        if failing { throw Failure() }
        if let index = recorded.firstIndex(where: { $0.id == focus.id }) {
            recorded[index].completedAt = focus.completedAt
            recorded[index].focusSeconds = focus.focusSeconds
        } else {
            recorded.append(focus)
        }
    }

    func sessions(on day: Date, calendar: Calendar) throws -> [FocusRow] {
        if failing { throw Failure() }
        return recorded.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }.map(\.row)
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
    func showFocusDone(completedToday: Int, breakDuration: TimeInterval, lingers: Bool) {
        calls.append(lingers ? "done" : "done-quietly")
        lastCompletedToday = completedToday
        lastBreakDuration = breakDuration
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
final class SpyAlarm: EndAlarming {
    var calls: [String] = []
    var permission: AlarmPermission = .authorized
    /// What the permission prompt would answer.
    var answer: AlarmPermission = .authorized
    var flushes = 0

    func requestPermission() async -> AlarmPermission {
        calls.append("ask")
        permission = answer
        return answer
    }
    func schedule(for session: ActiveSession) { calls.append("schedule") }
    func cancel() { calls.append("cancel") }
    func flush() async { flushes += 1 }
    /// Stands in for the system: call it to start or stop the ringing.
    var ring: (@Sendable @MainActor (Bool) -> Void)?
    func watchRinging(_ report: @escaping @Sendable @MainActor (Bool) -> Void) { ring = report }
}

@MainActor
final class SpyMindful: MindfulLogging {
    var permission: HealthPermission = .authorized
    /// What the permission prompt would answer.
    var answer: HealthPermission = .authorized
    var asked = 0
    var saved: [CompletedFocus] = []
    var removed: [UUID] = []
    var removedAll = 0
    var flushes = 0

    func requestPermission() async -> HealthPermission {
        asked += 1
        permission = answer
        return answer
    }
    func save(_ focus: CompletedFocus) { saved.append(focus) }
    func remove(ids: [UUID]) { removed += ids }
    func removeAll() { removedAll += 1 }
    func flush() async { flushes += 1 }
}

@MainActor
final class SpyWidgets: WidgetReloading {
    var reloads = 0
    var lastSnapshot: WidgetSnapshot?
    func reload(with snapshot: WidgetSnapshot) {
        reloads += 1
        lastSnapshot = snapshot
    }
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

@MainActor
final class SpySounds: TimerSounds {
    var played: [TimerSound] = []
    func play(_ sound: TimerSound) { played.append(sound) }
}
