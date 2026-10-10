import UserNotifications

/// What AppServices needs from the end-of-phase alert, so tests can stand in for it.
@MainActor
protocol EndNotifying: AnyObject {
    func schedule(for session: ActiveSession)
    func cancel()
    func authorizationStatus() async -> UNAuthorizationStatus
}

/// A local, on-device notification at the end of a running phase.
@MainActor
final class EndNotifier: EndNotifying {
    private static let id = "clockin.phase-end"
    private let center = UNUserNotificationCenter.current()
    /// Bumped by every schedule and cancel, so a request still waiting on the
    /// permission prompt is dropped if the session changed in the meantime.
    private var generation = 0

    /// Asks for permission the first time it's needed (the first Start), not
    /// at launch, then schedules the alert for the phase's end.
    func schedule(for session: ActiveSession) {
        cancel()
        guard let end = session.endDate, end.timeIntervalSinceNow > 1 else { return }
        let content = Self.content(for: session)
        let generation = generation
        Task {
            guard await authorize(), generation == self.generation else { return }
            let interval = end.timeIntervalSinceNow
            guard interval > 1 else { return }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: Self.id, content: content, trigger: trigger))
            } catch {
                Log.notifications.error("Couldn't schedule the end alert: \(error)")
            }
        }
    }

    func cancel() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [Self.id])
        center.removeDeliveredNotifications(withIdentifiers: [Self.id])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private func authorize() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                Log.notifications.error("Notification authorization failed: \(error)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func content(for session: ActiveSession) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch session.phase {
        case .focus:
            content.title = "Focus complete"
            content.body = "\(session.name) is done. Time for a \(Durations.breakLengthPhrase) break."
        case .rest:
            content.title = "Break's over"
            content.body = "Ready for the next session?"
        }
        content.sound = .default
        // Breaks through Focus only with the time-sensitive entitlement (see
        // project.yml); without it the system delivers at the normal level.
        content.interruptionLevel = .timeSensitive
        return content
    }
}

/// Plays the end sound when a phase finishes while Clockin is open. Without a
/// delegate, iOS drops notifications for the foreground app entirely.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // The screen already shows the finished timer; a banner would repeat it.
        [.sound, .list]
    }
}
