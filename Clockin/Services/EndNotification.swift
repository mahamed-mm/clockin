import UserNotifications

/// What AppServices needs from the end-of-phase alert, so tests can stand in for it.
@MainActor
protocol EndNotifying: AnyObject {
    func schedule(for session: ActiveSession)
    func cancel()
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Waits until a schedule still in flight has reached the system.
    func flush() async
}

/// A local, on-device notification at the end of a running phase.
@MainActor
final class EndNotifier: EndNotifying {
    private static let id = "clockin.phase-end"
    private let center = UNUserNotificationCenter.current()
    /// Bumped by every schedule and cancel, so a request still waiting on the
    /// permission prompt is dropped if the session changed in the meantime.
    private var generation = 0
    /// Known to be allowed, so scheduling needn't wait on a settings round trip.
    private var isAuthorized = false
    private var inFlight: Task<Void, Never>?

    /// Asks for permission the first time it's needed (the first Start), not
    /// at launch, then schedules the alert for the phase's end. Once permission
    /// is known, the request goes out in the caller's turn, which matters when
    /// a Lock Screen intent resumes the session and the app may be suspended next.
    func schedule(for session: ActiveSession) {
        cancel()
        guard let end = session.endDate, end.timeIntervalSinceNow > 1 else { return }
        let content = Self.content(for: session)
        if isAuthorized {
            add(content, endingAt: end)
            return
        }
        let generation = generation
        inFlight = Task {
            guard await authorize(), generation == self.generation else { return }
            add(content, endingAt: end)
        }
    }

    func flush() async {
        await inFlight?.value
    }

    private func add(_ content: UNNotificationContent, endingAt end: Date) {
        let interval = end.timeIntervalSinceNow
        guard interval > 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.id, content: content, trigger: trigger)) { error in
            if let error {
                Log.notifications.error("Couldn't schedule the end alert: \(error, privacy: .public)")
            }
        }
    }

    func cancel() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [Self.id])
        center.removeDeliveredNotifications(withIdentifiers: [Self.id])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let status = await center.notificationSettings().authorizationStatus
        isAuthorized = Self.allows(status)
        return status
    }

    private static func allows(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private func authorize() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
                return isAuthorized
            } catch {
                Log.notifications.error("Notification authorization failed: \(error, privacy: .public)")
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
            content.title = Copy.focusComplete
            content.subtitle = Copy.displayName(session.name)
            content.body = Copy.breakLine(seconds: session.nextBreakSeconds ?? Preset.classic.shortBreak)
        case .rest:
            content.title = Copy.breakOver
            content.body = Copy.readyWhenYouAre
        }
        content.sound = UNNotificationSound(named: UNNotificationSoundName(ChimeSound.fileName))
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
