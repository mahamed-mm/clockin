import ActivityKit
import Foundation

/// Mirrors the active session into a Live Activity on the Lock Screen
/// and in the Dynamic Island.
@MainActor
final class LiveActivityController {
    func sync(with session: ActiveSession, completedToday: Int) {
        let state = FocusActivityAttributes.ContentState(session: session, completedToday: completedToday)
        let content = ActivityContent(state: state, staleDate: session.endDate)
        let name = session.name
        Task { await LiveActivities.sync(name: name, content: content) }
    }

    /// Leaves a "focus done" card on the Lock Screen until the user moves on.
    func showFocusDone(completedToday: Int) {
        Task { await LiveActivities.endRunningAsDone(completedToday: completedToday) }
    }

    func endAll() {
        Task { await LiveActivities.endAll() }
    }
}

/// ActivityKit calls, kept off the main actor because `Activity` isn't Sendable.
private enum LiveActivities {
    typealias Content = ActivityContent<FocusActivityAttributes.ContentState>

    private static var running: Activity<FocusActivityAttributes>? {
        Activity<FocusActivityAttributes>.activities.first { $0.activityState == .active }
    }

    @concurrent
    static func sync(name: String, content: Content) async {
        if let activity = running, activity.attributes.sessionName == name {
            await activity.update(content)
            return
        }
        await endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: FocusActivityAttributes(sessionName: name),
                                  content: content)
    }

    @concurrent
    static func endRunningAsDone(completedToday: Int) async {
        guard let activity = running else { return }
        var state = activity.content.state
        state.completedToday = completedToday
        state.pausedRemaining = nil
        state.endDate = min(state.endDate ?? .now, .now)
        await activity.end(Content(state: state, staleDate: nil), dismissalPolicy: .default)
    }

    @concurrent
    static func endAll() async {
        for activity in Activity<FocusActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
