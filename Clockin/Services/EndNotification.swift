import UserNotifications

/// A local, on-device notification at the end of a running phase.
enum EndNotification {
    private static let id = "clockin.phase-end"

    static func requestAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    @MainActor
    static func schedule(for session: ActiveSession) {
        cancel()
        guard let end = session.endDate else { return }
        let interval = end.timeIntervalSinceNow
        guard interval > 1 else { return }

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
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
