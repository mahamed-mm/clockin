import ActivityKit
import Foundation

/// What AppServices needs from the Live Activity, so tests can stand in for it.
@MainActor
protocol LiveActivityControlling: AnyObject {
    func sync(with session: ActiveSession, completedToday: Int, breakDuration: TimeInterval)
    /// Leaves a "focus done" card on the Lock Screen until the user moves on.
    func showFocusDone(completedToday: Int)
    func endAll()
    func areActivitiesEnabled() async -> Bool
    /// Waits until every queued ActivityKit call has run.
    func flush() async
}

/// Mirrors the active session into a Live Activity on the Lock Screen
/// and in the Dynamic Island.
@MainActor
final class LiveActivityController: LiveActivityControlling {
    /// The most recently queued ActivityKit call. Each call waits for the one
    /// before it, so an end can never overtake the request queued after it.
    private var queue: Task<Void, Never>?

    func sync(with session: ActiveSession, completedToday: Int, breakDuration: TimeInterval) {
        let state = FocusActivityAttributes.ContentState(session: session, completedToday: completedToday,
                                                         breakDuration: breakDuration)
        let content = ActivityContent(state: state, staleDate: session.endDate)
        let name = session.name
        enqueue { await LiveActivities.sync(name: name, content: content) }
    }

    func showFocusDone(completedToday: Int) {
        enqueue { await LiveActivities.endRunningAsDone(completedToday: completedToday) }
    }

    func endAll() {
        enqueue { await LiveActivities.endAll() }
    }

    func areActivitiesEnabled() async -> Bool {
        await LiveActivities.areEnabled()
    }

    func flush() async {
        await queue?.value
    }

    /// Whether an activity in this state is still showing a session. A running
    /// activity turns `.stale` once its end date passes, which is exactly when
    /// a finished session needs to find it.
    nonisolated static func isShowingSession(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    private func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await operation()
        }
    }
}

/// ActivityKit calls, kept off the main actor: `Activity` isn't Sendable, and
/// reading `Activity.activities` is a synchronous XPC that can stall.
private enum LiveActivities {
    typealias Content = ActivityContent<FocusActivityAttributes.ContentState>

    private static var running: Activity<FocusActivityAttributes>? {
        Activity<FocusActivityAttributes>.activities.first {
            LiveActivityController.isShowingSession($0.activityState)
        }
    }

    @concurrent
    static func sync(name: String, content: Content) async {
        if let activity = running, activity.attributes.sessionName == name {
            await activity.update(content)
            return
        }
        await endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: FocusActivityAttributes(sessionName: name), content: content)
        } catch {
            Log.liveActivity.error("Couldn't start a Live Activity: \(error, privacy: .public)")
        }
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

    @concurrent
    static func areEnabled() async -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
}
