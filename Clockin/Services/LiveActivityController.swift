import ActivityKit
import Foundation

/// What AppServices needs from the Live Activity, so tests can stand in for it.
@MainActor
protocol LiveActivityControlling: AnyObject {
    func sync(with session: ActiveSession, completedToday: Int, breakDuration: TimeInterval, symbol: String,
              canExtend: Bool)
    /// Turns the session's card to a "focus done" note naming the break it
    /// earned, with Start break. With `lingers` it stays on the Lock Screen,
    /// still live so its button works, until the user moves on; without, it
    /// goes at once, for a completion only noticed long after the fact.
    func showFocusDone(completedToday: Int, breakDuration: TimeInterval, lingers: Bool)
    /// Turns a break's card to "Break's over" with Start focus, still live.
    func showBreakDone()
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

    func sync(with session: ActiveSession, completedToday: Int, breakDuration: TimeInterval, symbol: String,
              canExtend: Bool) {
        let state = FocusActivityAttributes.ContentState(session: session, completedToday: completedToday,
                                                         breakDuration: breakDuration, symbol: symbol,
                                                         canExtend: canExtend ? true : nil)
        let content = ActivityContent(state: state, staleDate: session.endDate)
        // Capped here too, for a long name saved by a build that didn't cap.
        let attributes = FocusActivityAttributes(sessionName: ActiveSession.cleanName(session.name),
                                                 sessionID: session.id)
        enqueue { await LiveActivities.sync(attributes: attributes, content: content) }
    }

    func showFocusDone(completedToday: Int, breakDuration: TimeInterval, lingers: Bool) {
        enqueue {
            await LiveActivities.endRunningAsDone(completedToday: completedToday, breakDuration: breakDuration,
                                                  lingers: lingers)
        }
    }

    func showBreakDone() {
        enqueue { await LiveActivities.showBreakDone() }
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

    /// Updates the session's card, or replaces whatever is showing with one.
    /// A card from a build before ids is matched by name and updated in place:
    /// replacing it can fail when this runs from the Lock Screen button with
    /// the app in the background, where new cards can't be requested.
    @concurrent
    static func sync(attributes: FocusActivityAttributes, content: Content) async {
        if let activity = running, isSameSession(activity.attributes, attributes) {
            await activity.update(content)
            return
        }
        await endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: attributes, content: content)
        } catch {
            Log.liveActivity.error("Couldn't start a Live Activity: \(error, privacy: .public)")
        }
    }

    private static func isSameSession(_ shown: FocusActivityAttributes, _ wanted: FocusActivityAttributes) -> Bool {
        if let id = shown.sessionID { return id == wanted.sessionID }
        return shown.sessionName == wanted.sessionName
    }

    @concurrent
    static func endRunningAsDone(completedToday: Int, breakDuration: TimeInterval, lingers: Bool) async {
        guard let activity = running else { return }
        var state = activity.content.state
        state.completedToday = completedToday
        state.breakDuration = breakDuration
        state.pausedRemaining = nil
        state.endDate = min(state.endDate ?? .now, .now)
        state.canExtend = nil
        // Updated rather than ended, so Start break still works from the Lock Screen.
        if lingers {
            await activity.update(Content(state: state, staleDate: nil))
        } else {
            await activity.end(Content(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    @concurrent
    static func showBreakDone() async {
        guard let activity = running, activity.content.state.phase == .rest else { return }
        var state = activity.content.state
        state.pausedRemaining = nil
        state.endDate = min(state.endDate ?? .now, .now)
        await activity.update(Content(state: state, staleDate: nil))
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
