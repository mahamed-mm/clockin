import ActivityKit
import AlarmKit
import SwiftUI

/// Whether Clockin may ring alarms.
enum AlarmPermission: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// What AppServices needs from the end-of-phase alarm, so tests can stand in for it.
@MainActor
protocol EndAlarming: AnyObject {
    var permission: AlarmPermission { get }
    /// Asks the first time; afterwards just says what was chosen.
    func requestPermission() async -> AlarmPermission
    /// Sets the alarm for the end of a running phase, replacing any other.
    func schedule(for session: ActiveSession)
    /// Takes the alarm away, and silences it if it's ringing.
    func cancel()
    /// Waits until a schedule still in flight has reached the system.
    func flush() async
}

/// An AlarmKit alarm at the end of a running phase. It sounds through
/// Silent mode and Focus, and rings, repeating the chime, until it's
/// stopped. The Live Activity stays the countdown; this is only the alert.
@MainActor
final class EndAlarm: EndAlarming {
    /// One alarm at a time, under one id, so it can be found after a relaunch.
    private nonisolated static let id = UUID(uuidString: "C10C1A2B-7E57-4A1A-9D0E-000000000001")!
    /// Bumped by every schedule and cancel, so a schedule that lands after
    /// a later cancel takes itself back.
    private var generation = 0
    private var inFlight: Task<Void, Never>?

    var permission: AlarmPermission { Self.permission(AlarmManager.shared.authorizationState) }

    func requestPermission() async -> AlarmPermission {
        do {
            return Self.permission(try await Self.askForPermission())
        } catch {
            Log.notifications.error("Alarm authorization failed: \(error, privacy: .public)")
            return permission
        }
    }

    func schedule(for session: ActiveSession) {
        cancel()
        guard permission == .authorized, let end = session.endDate, end.timeIntervalSinceNow > 1 else { return }
        let generation = generation
        inFlight = Task {
            do {
                try await Self.set(for: session, endingAt: end)
                // Cancelled or replaced while the system was taking it.
                if generation != self.generation { try? AlarmManager.shared.cancel(id: Self.id) }
            } catch {
                Log.notifications.error("Couldn't schedule the end alarm: \(error, privacy: .public)")
            }
        }
    }

    func cancel() {
        generation += 1
        // Both throw when there's no such alarm, which is fine: there's nothing to stop.
        try? AlarmManager.shared.stop(id: Self.id)
        try? AlarmManager.shared.cancel(id: Self.id)
    }

    // AlarmManager isn't Sendable, so its async calls are made away from the main actor.

    @concurrent
    private nonisolated static func askForPermission() async throws -> AlarmManager.AuthorizationState {
        try await AlarmManager.shared.requestAuthorization()
    }

    @concurrent
    private nonisolated static func set(for session: ActiveSession, endingAt end: Date) async throws {
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration(for: session, endingAt: end))
    }

    func flush() async {
        await inFlight?.value
    }

    private static func permission(_ state: AlarmManager.AuthorizationState) -> AlarmPermission {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    private nonisolated static func configuration(for session: ActiveSession,
                                      endingAt end: Date) -> AlarmManager.AlarmConfiguration<ClockinAlarm> {
        let focus = session.phase == .focus
        let title = LocalizedStringResource(stringLiteral: focus ? Copy.focusComplete : Copy.breakOver)
        // After focus, the alarm offers the break; after a break there's
        // nothing to start, so it only stops.
        let startBreak = AlarmButton(text: LocalizedStringResource(stringLiteral: Copy.startBreakShort),
                                     textColor: .white, systemImageName: "cup.and.saucer.fill")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: focus ? startBreak : nil,
                                            secondaryButtonBehavior: focus ? .custom : nil)
        } else {
            let stop = AlarmButton(text: LocalizedStringResource(stringLiteral: Copy.stopAlarm), textColor: .white,
                                   systemImageName: "stop.circle")
            alert = AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: focus ? startBreak : nil,
                                            secondaryButtonBehavior: focus ? .custom : nil)
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: ClockinAlarm(),
                                         tintColor: Retro.tint(for: session.phase))
        return .alarm(schedule: .fixed(end), attributes: attributes,
                      secondaryIntent: focus ? StartBreakIntent(sessionID: session.id) : nil,
                      sound: .named(ChimeSound.fileName))
    }
}

/// No alarm, for previews and for tests that don't care about one.
@MainActor
final class NoAlarm: EndAlarming {
    var permission: AlarmPermission { .notDetermined }
    func requestPermission() async -> AlarmPermission { .notDetermined }
    func schedule(for session: ActiveSession) {}
    func cancel() {}
    func flush() async {}
}

/// The chime both alerts play: 24 seconds of a warm two-note bell, made by
/// scripts/make-chime.sh. The alarm repeats it until it's stopped.
enum ChimeSound {
    static let fileName = "clockin-ding.caf"
}
