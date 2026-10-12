import Foundation
import Observation

/// Things that happen to a session. The app turns these into haptics,
/// Live Activity updates, notifications, and widget reloads.
enum SessionEvent: Equatable, Sendable {
    case started
    case paused
    case resumed
    case cancelled
    case focusCompleted(Freshness)
    case breakStarted
    case breakFinished(Freshness)
    case breakSkipped
    /// The user moved on from "focus complete" without starting a break.
    case completionDismissed
    /// The session is back: after a relaunch, or when a cancel is undone.
    case restored
    /// Finished sessions that were waiting to be saved reached History.
    case historySaved
}

/// How soon after a phase ended the engine noticed, which sets how loudly
/// the app reacts.
enum Freshness: Equatable, Sendable {
    /// The timer ran out while the app was open.
    case live
    /// Noticed a little later on the same day, e.g. after tapping the alert.
    case recent
    /// Long enough ago, or on an earlier day, that celebrating would be odd.
    case stale

    /// An ending stays `recent` for `recentWindow`: the length of the break
    /// that follows a focus phase, or of the break itself.
    static func of(endedAt: Date, now: Date, recentWindow: TimeInterval, calendar: Calendar) -> Freshness {
        let age = now.timeIntervalSince(endedAt)
        if age < 3 { return .live }
        if age < recentWindow, calendar.isDate(endedAt, inSameDayAs: now) { return .recent }
        return .stale
    }
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
    /// How long Cancel can be undone, normally.
    static let standardUndoWindow: TimeInterval = 6

    private(set) var stage: SessionStage = .idle
    /// The focus phase cancelled moments ago, so it can be brought back.
    /// Cleared by any other transition and when the undo window closes.
    private(set) var undoableCancel: ActiveSession?
    /// How long Cancel can be undone, asked at each cancel. The app gives
    /// assistive technologies longer, since reaching Undo takes them longer.
    @ObservationIgnored var undoWindow: @MainActor () -> TimeInterval = { SessionEngine.standardUndoWindow }
    /// The lengths for the next session, read when it starts. The app
    /// supplies them from Settings.
    @ObservationIgnored var plan: @MainActor () -> TimerPlan = { .classic }

    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let store: SessionStateStoring
    @ObservationIgnored private let log: FocusLogging
    @ObservationIgnored weak var effects: SessionEffects?
    /// Off in tests, which move time by hand: no completion or undo timers.
    @ObservationIgnored private let schedulesCompletion: Bool
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var undoDeadline: Date?
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?
    /// Finished sessions the log refused; saved with the state and retried.
    /// Observed, so today's totals can include them while they wait.
    private(set) var pendingRecords: [CompletedFocus]

    init(now: @escaping () -> Date = Date.init,
         calendar: Calendar = .autoupdatingCurrent,
         store: SessionStateStoring,
         log: FocusLogging,
         schedulesCompletion: Bool = true) {
        self.now = now
        self.calendar = calendar
        self.store = store
        self.log = log
        self.schedulesCompletion = schedulesCompletion
        let saved = store.load()
        pendingRecords = saved.pendingRecords ?? []
        if let active = saved.active {
            stage = .active(active)
        } else if let focus = saved.completedFocus {
            stage = .focusComplete(focus)
        } else if saved.completedFocusName != nil {
            // 1.0 kept only the name, so the completion can't be dated. The
            // session is already in History; offering a break now would be a guess.
            Log.store.info("Dropping an undated completion from an older build")
        }
    }

    // MARK: - Queries

    var active: ActiveSession? {
        if case .active(let session) = stage { return session }
        return nil
    }

    var hasActiveSession: Bool { active != nil }

    /// Sessions waiting to be saved that finished on `day`.
    func pendingRecords(on day: Date) -> [CompletedFocus] {
        pendingRecords.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }
    }

    /// How current a completed focus phase is at `date`. It stays recent
    /// for as long as the break it earned.
    func freshness(of focus: CompletedFocus, at date: Date) -> Freshness {
        Freshness.of(endedAt: focus.completedAt, now: date, recentWindow: breakLength(after: focus),
                     calendar: calendar)
    }

    /// The break a completed focus phase earned.
    func breakLength(after focus: CompletedFocus) -> TimeInterval {
        focus.breakSeconds ?? plan().shortBreak
    }

    // MARK: - Actions

    /// Starts a focus phase. Returns false if a session is already active.
    @discardableResult
    func start(name: String) -> Bool {
        guard !hasActiveSession else { return false }
        let plan = plan()
        let startedAt = now()
        // The break it will most likely earn, for the end alert and the
        // Lock Screen. Settled for real when it ends.
        let predicted = plan.breaks.after(position: fullSessions(on: startedAt) + 1)
        let session = ActiveSession(
            id: UUID(),
            name: ActiveSession.cleanName(name),
            phase: .focus,
            plannedDuration: plan.focus,
            focusStartedAt: startedAt,
            state: .running(endDate: startedAt.addingTimeInterval(plan.focus)),
            nextBreakSeconds: predicted.seconds,
            breaks: plan.breaks
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

    /// For the Lock Screen button: moves toward what the button showed, and
    /// only for the session it was drawn for (`nil` matches any), so a second
    /// tap or a card left from an older session can't flip the timer back.
    func setPaused(_ paused: Bool, sessionID: UUID?) {
        guard let session = active, sessionID == nil || sessionID == session.id else { return }
        paused ? pause() : resume()
    }

    /// Cancels the focus phase without recording anything. It can be undone
    /// until the undo window closes.
    func cancel() {
        guard let session = active, session.phase == .focus else { return }
        apply(.idle, event: .cancelled)
        let window = undoWindow()
        undoableCancel = session
        undoDeadline = now().addingTimeInterval(window)
        scheduleUndoExpiry(after: window)
    }

    /// Brings back the focus phase just cancelled, exactly as it was: a
    /// running timer kept running in the meantime, a paused one stayed paused.
    func undoCancel() {
        guard case .idle = stage, let session = undoableCancel, let undoDeadline,
              now() <= undoDeadline else { return }
        guard !session.isFinished(at: now()) else {
            // It ran out while cancelled: complete it, without first putting
            // a card for a finished session back on the Lock Screen.
            clearUndo()
            stage = .active(session)
            reconcile()
            return
        }
        apply(.active(session), event: .restored)
    }

    func startBreak() {
        guard case .focusComplete(let focus) = stage else { return }
        let duration = breakLength(after: focus)
        let start = now()
        let session = ActiveSession(
            id: UUID(),
            name: focus.name,
            phase: .rest,
            plannedDuration: duration,
            focusStartedAt: start,
            state: .running(endDate: start.addingTimeInterval(duration)),
            isLongBreak: focus.isLongBreak
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
        retimeAfterClockSetBack()
        guard let session = active, session.isFinished(at: now()) else {
            scheduleCompletionCheck()
            return
        }
        let endedAt = session.endDate ?? now()
        switch session.phase {
        case .focus:
            var focus = CompletedFocus(id: session.id, name: session.name, startedAt: session.focusStartedAt,
                                       completedAt: endedAt, focusSeconds: session.plannedDuration,
                                       plannedSeconds: session.plannedDuration, outcome: .completed)
            settleBreak(for: &focus, from: session)
            record(focus)
            apply(.focusComplete(focus), event: .focusCompleted(freshness(of: focus, at: now())))
        case .rest:
            let freshness = Freshness.of(endedAt: endedAt, now: now(), recentWindow: session.plannedDuration,
                                         calendar: calendar)
            apply(.idle, event: .breakFinished(freshness))
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

    /// Full sessions that finished on the day containing `date`, saved or
    /// waiting to be saved, other than `excluded`.
    private func fullSessions(on date: Date, excluding excluded: UUID? = nil) -> Int {
        let saved: [FocusRow]
        do {
            saved = try log.sessions(on: date, calendar: calendar)
        } catch {
            Log.store.error("Couldn't count today's sessions: \(error, privacy: .public)")
            saved = []
        }
        return TodayStats.rows(saved: saved, pending: pendingRecords(on: date)).filter { $0.id != excluded }.fullCount
    }

    /// Picks the break a focus phase earned, now that it has ended: the long
    /// one if it completes a set on the day it ended. A session that doesn't
    /// fill a pill doesn't move the set on, so it gets the short one.
    private func settleBreak(for focus: inout CompletedFocus, from session: ActiveSession) {
        let breaks = session.breaks ?? BreakLengths(short: session.nextBreakSeconds ?? plan().shortBreak)
        let position = focus.countsAsFull ? fullSessions(on: focus.completedAt, excluding: focus.id) + 1 : 0
        let earned = breaks.after(position: position)
        focus.breakSeconds = earned.seconds
        focus.isLongBreak = earned.isLong
    }

    /// A running phase can't end further away than its full length unless the
    /// clock was set back. Rather than sit frozen at the full length until the
    /// clock catches up, it starts counting down again from there.
    private func retimeAfterClockSetBack() {
        guard var session = active, let end = session.endDate,
              end.timeIntervalSince(now()) > session.plannedDuration + 1 else { return }
        session.state = .running(endDate: now().addingTimeInterval(session.plannedDuration))
        apply(.active(session), event: .restored)
    }

    private func apply(_ newStage: SessionStage, event: SessionEvent) {
        clearUndo()
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
            Log.store.error("Couldn't save a finished session; keeping it to retry: \(error, privacy: .public)")
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
            effects?.sessionEngine(self, didEmit: .historySaved)
        }
    }

    private func persist() {
        var state = PersistedSessionState()
        switch stage {
        case .idle: break
        case .active(let session): state.active = session
        case .focusComplete(let focus): state.completedFocus = focus
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

    private func scheduleUndoExpiry(after window: TimeInterval) {
        undoExpiry?.cancel()
        guard schedulesCompletion else { return }
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            self?.clearUndo()
        }
    }

    private func clearUndo() {
        undoExpiry?.cancel()
        undoExpiry = nil
        undoableCancel = nil
        undoDeadline = nil
    }
}
