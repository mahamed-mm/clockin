import Foundation
import Observation

/// Things that happen to a session. The app turns these into haptics,
/// Live Activity updates, notifications, and widget reloads.
enum SessionEvent: Equatable, Sendable {
    case started
    case paused
    case resumed
    case cancelled
    /// `live` is false when the completion was discovered on relaunch/foreground.
    case focusCompleted(live: Bool)
    case breakStarted
    case breakFinished
    case breakSkipped
    /// The user moved on from "focus complete" without starting a break.
    case completionDismissed
    case restored
}

@MainActor
protocol SessionEffects: AnyObject {
    func sessionEngine(_ engine: SessionEngine, didEmit event: SessionEvent)
}

/// Date-based timer state machine. Remaining time is always derived from
/// the end date, so it stays correct in the background and across relaunches.
@MainActor
@Observable
final class SessionEngine {
    private(set) var stage: SessionStage = .idle

    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private let store: SessionStateStoring
    @ObservationIgnored private let log: FocusLogging
    @ObservationIgnored weak var effects: SessionEffects?
    @ObservationIgnored private let schedulesCompletion: Bool
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    /// Finished sessions the log refused; saved with the state and retried.
    @ObservationIgnored private(set) var pendingRecords: [CompletedFocus]

    init(now: @escaping () -> Date = Date.init,
         store: SessionStateStoring,
         log: FocusLogging,
         schedulesCompletion: Bool = true) {
        self.now = now
        self.store = store
        self.log = log
        self.schedulesCompletion = schedulesCompletion
        let saved = store.load()
        pendingRecords = saved.pendingRecords ?? []
        if let active = saved.active {
            stage = .active(active)
        } else if let name = saved.completedFocusName {
            stage = .focusComplete(name: name)
        }
    }

    // MARK: - Queries

    var active: ActiveSession? {
        if case .active(let session) = stage { return session }
        return nil
    }

    var hasActiveSession: Bool { active != nil }

    // MARK: - Actions

    /// Starts a focus phase. Returns false if a session is already active.
    @discardableResult
    func start(name: String) -> Bool {
        guard !hasActiveSession else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = Durations.duration(for: .focus)
        let startedAt = now()
        let session = ActiveSession(
            id: UUID(),
            name: trimmed.isEmpty ? "Focus" : trimmed,
            phase: .focus,
            plannedDuration: duration,
            focusStartedAt: startedAt,
            state: .running(endDate: startedAt.addingTimeInterval(duration))
        )
        apply(.active(session), event: .started)
        return true
    }

    func pause() {
        guard var session = active, case .running = session.state else { return }
        let remaining = session.remaining(at: now())
        guard remaining > 0 else { reconcile(); return }
        session.state = .paused(remaining: remaining)
        apply(.active(session), event: .paused)
    }

    func resume() {
        guard var session = active, case .paused(let remaining) = session.state else { return }
        session.state = .running(endDate: now().addingTimeInterval(remaining))
        apply(.active(session), event: .resumed)
    }

    func togglePause() {
        guard let session = active else { return }
        session.isPaused ? resume() : pause()
    }

    /// Cancels the focus phase without recording anything.
    func cancel() {
        guard let session = active, session.phase == .focus else { return }
        apply(.idle, event: .cancelled)
    }

    func startBreak() {
        guard case .focusComplete(let name) = stage else { return }
        let duration = Durations.duration(for: .rest)
        let start = now()
        let session = ActiveSession(
            id: UUID(),
            name: name,
            phase: .rest,
            plannedDuration: duration,
            focusStartedAt: start,
            state: .running(endDate: start.addingTimeInterval(duration))
        )
        apply(.active(session), event: .breakStarted)
    }

    /// Ends a break early, or dismisses the "focus complete" state.
    func skipBreak() {
        switch stage {
        case .active(let session) where session.phase == .rest:
            apply(.idle, event: .breakSkipped)
        case .focusComplete:
            apply(.idle, event: .completionDismissed)
        default:
            break
        }
    }

    /// Checks whether the current phase has run out. Call on launch, when
    /// returning to the foreground, and when the scheduled end fires.
    func reconcile() {
        retryPendingRecords()
        guard let session = active, session.isFinished(at: now()) else {
            scheduleCompletionCheck()
            return
        }
        switch session.phase {
        case .focus:
            let completedAt = session.endDate ?? now()
            record(CompletedFocus(id: session.id, name: session.name, startedAt: session.focusStartedAt,
                                  completedAt: completedAt, focusSeconds: session.plannedDuration))
            let live = now().timeIntervalSince(completedAt) < 3
            apply(.focusComplete(name: session.name), event: .focusCompleted(live: live))
        case .rest:
            apply(.idle, event: .breakFinished)
        }
    }

    /// Re-announces current state after launch so side effects (Live Activity, widget) resync.
    func restore() {
        reconcile()
        if hasActiveSession {
            effects?.sessionEngine(self, didEmit: .restored)
        }
    }

    // MARK: - Internals

    private func apply(_ newStage: SessionStage, event: SessionEvent) {
        stage = newStage
        persist()
        scheduleCompletionCheck()
        effects?.sessionEngine(self, didEmit: event)
    }

    /// Saves a finished focus phase. If the log can't take it, it waits in
    /// the persisted state (saved by the transition that follows) and is
    /// retried on the next reconcile, so a completed session is never lost.
    private func record(_ focus: CompletedFocus) {
        do {
            try log.record(focus)
        } catch {
            Log.store.error("Couldn't save a finished session; keeping it to retry: \(error)")
            pendingRecords.append(focus)
        }
    }

    private func retryPendingRecords() {
        guard !pendingRecords.isEmpty else { return }
        let before = pendingRecords.count
        pendingRecords = pendingRecords.filter { focus in
            do {
                try log.record(focus)
                return false
            } catch {
                return true
            }
        }
        if pendingRecords.count != before {
            Log.store.info("Saved \(before - self.pendingRecords.count) pending session(s)")
            persist()
        }
    }

    private func persist() {
        var state = PersistedSessionState()
        switch stage {
        case .idle: break
        case .active(let session): state.active = session
        case .focusComplete(let name): state.completedFocusName = name
        }
        state.pendingRecords = pendingRecords.isEmpty ? nil : pendingRecords
        store.save(state)
    }

    private func scheduleCompletionCheck() {
        completionTask?.cancel()
        completionTask = nil
        guard schedulesCompletion, let end = active?.endDate else { return }
        let delay = max(0, end.timeIntervalSince(now()))
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }
}
