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
    /// Minutes were added to the focus phase.
    case extended
    /// The focus phase was finished early; its minutes were kept.
    case finishedEarly
    /// Minutes worked past the bell were added to the finished session.
    case overtimeKept
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
    /// "+5 min": offered in the last this-many seconds, and added each time.
    nonisolated static let extensionStep: TimeInterval = 5 * 60
    /// The most "+5 min" can add to one session.
    static let maxExtension: TimeInterval = 15 * 60
    /// Before this much focus, Cancel (which can be undone) is the honest way out.
    static let minimumToFinishEarly: TimeInterval = 60
    /// After the bell, the dial counts the time you kept going for this
    /// long, so it can be added to the session.
    static let maxOvertime: TimeInterval = 60 * 60

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
    /// How a break starts out, read when it starts. The app supplies it from Settings.
    @ObservationIgnored var breakStyle: @MainActor () -> BreakStyle = { .rest }
    /// What plays through a focus session, read when it starts. The app supplies it from Settings.
    @ObservationIgnored var focusSound: @MainActor () -> FocusSound = { .off }

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
    /// A break that ran out moments ago, while the app should say so. Set
    /// only when a break runs to its end; any other change clears it.
    private(set) var breakOver: BreakOverMoment?
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
        } else if let moment = saved.breakOver, moment.isShowing(at: now(), calendar: calendar) {
            breakOver = moment
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

    /// When "Break's over" stops showing on its own, while it shows.
    var breakOverEnds: Date? { breakOver?.ends(calendar: calendar) }

    /// The break a completed focus phase earned.
    func breakLength(after focus: CompletedFocus) -> TimeInterval {
        focus.breakSeconds ?? plan().shortBreak
    }

    /// Whether "+5 min" is on offer: the last five minutes of a focus phase,
    /// up to `maxExtension` in all.
    func canExtend(at date: Date) -> Bool {
        guard let session = active, session.phase == .focus, !session.isFinished(at: date) else { return false }
        return session.remaining(at: date) <= Self.extensionStep
            && (session.extendedSeconds ?? 0) + Self.extensionStep <= Self.maxExtension
    }

    /// Whether "Finish now" is on offer: a focus phase past its first minute
    /// (or its first tenth, for seconds-long test timers).
    func canFinishEarly(at date: Date) -> Bool {
        guard let session = active, session.phase == .focus, !session.isFinished(at: date) else { return false }
        let minimum = min(Self.minimumToFinishEarly, session.originalPlan / 10)
        return session.plannedDuration - session.remaining(at: date) >= minimum
    }

    /// The moments after `date` when "+5 min" or "Finish now" appear or
    /// go away, so the screen can redraw just then. None while paused.
    func controlChanges(after date: Date) -> [Date] {
        guard let session = active, session.phase == .focus, let end = session.endDate else { return [] }
        let unlocksFinish = end.addingTimeInterval(
            -(session.plannedDuration - min(Self.minimumToFinishEarly, session.originalPlan / 10)))
        let opensExtend = end.addingTimeInterval(-Self.extensionStep)
        return [unlocksFinish, opensExtend, end].filter { $0 > date }.sorted()
    }

    /// How long ago a focus phase ran out, while that time can still be
    /// kept: only after a full session, once, and within `maxOvertime`.
    func overtime(at date: Date) -> TimeInterval? {
        guard case .focusComplete(let focus) = stage, (focus.outcome ?? .completed) == .completed,
              focus.keptOvertime == nil else { return nil }
        let over = date.timeIntervalSince(focus.completedAt)
        guard over >= 0, over <= Self.maxOvertime else { return nil }
        return over
    }

    /// The moments after `date` when overtime gains a minute, and when it
    /// runs out, so the screen redraws once a minute and no more.
    func overtimeChanges(after date: Date) -> [Date] {
        guard overtime(at: date) != nil, case .focusComplete(let focus) = stage else { return [] }
        let minutes = Int(Self.maxOvertime / 60)
        return (1...minutes).map { focus.completedAt.addingTimeInterval(TimeInterval($0) * 60) }
            .filter { $0 > date }
            + [focus.completedAt.addingTimeInterval(Self.maxOvertime + 1)].filter { $0 > date }
    }

    // MARK: - Actions

    /// Starts a focus phase. Returns false if a session is already active.
    /// A `length` (from Siri or Shortcuts) is for this session only; the
    /// next one goes back to the plan.
    @discardableResult
    func start(name: String, length: SessionLength? = nil) -> Bool {
        guard !hasActiveSession else { return false }
        var plan = plan()
        if let length {
            plan.focus = length.focus
            plan.shortBreak = length.shortBreak
        }
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
            breaks: plan.breaks,
            focusSound: focusSound() == .off ? nil : focusSound()
        )
        apply(.active(session), event: .started)
        return true
    }

    func pause() {
        guard var session = active, case .running = session.state else { return }
        let remaining = session.remaining(at: now())
        guard remaining > 0 else { reconcile(); return }
        session.state = .paused(remaining: remaining)
        session.pausedAt = now()
        apply(.active(session), event: .paused)
    }

    func resume() {
        guard var session = active, case .paused(let remaining) = session.state else { return }
        session.state = .running(endDate: now().addingTimeInterval(remaining))
        session.pausedAt = nil
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
        let window = undoWindow()
        // Undoable before anyone hears of it, so they can see what was cancelled.
        apply(.idle, event: .cancelled, undoable: session)
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

    /// Adds five minutes to the focus phase, running or paused.
    func extend() {
        reconcile()
        guard canExtend(at: now()), var session = active else { return }
        session.plannedDuration += Self.extensionStep
        session.extendedSeconds = (session.extendedSeconds ?? 0) + Self.extensionStep
        session.state = switch session.state {
        case .running(let end): .running(endDate: end.addingTimeInterval(Self.extensionStep))
        case .paused(let remaining): .paused(remaining: remaining + Self.extensionStep)
        }
        apply(.active(session), event: .extended)
    }

    /// Ends the focus phase now and keeps the minutes done so far. Time spent
    /// paused doesn't count. If the timer had already run out, it completes
    /// normally instead.
    func finishEarly() {
        reconcile()
        let now = now()
        guard canFinishEarly(at: now), let session = active else { return }
        let elapsed = (session.plannedDuration - session.remaining(at: now)).rounded(.down)
        var focus = CompletedFocus(id: session.id, name: session.name, startedAt: session.focusStartedAt,
                                   completedAt: now, focusSeconds: elapsed,
                                   plannedSeconds: session.originalPlan, outcome: .endedEarly,
                                   thoughts: session.thoughts)
        settleBreak(for: &focus, from: session)
        record(focus)
        apply(.focusComplete(focus), event: .finishedEarly)
    }

    /// Adds the whole minutes worked since the bell to the finished session,
    /// as focus. Its end moves on by the same amount.
    func keepOvertime() {
        guard case .focusComplete(var focus) = stage, let over = overtime(at: now()) else { return }
        let kept = (over / 60).rounded(.down) * 60
        guard kept >= 60 else { return }
        focus.focusSeconds += kept
        focus.completedAt = focus.completedAt.addingTimeInterval(kept)
        focus.keptOvertime = kept
        if let waiting = pendingRecords.firstIndex(where: { $0.id == focus.id }) {
            pendingRecords[waiting] = focus
        } else {
            do {
                try log.update(focus)
            } catch {
                Log.store.error("Couldn't add overtime to a saved session; keeping it to retry: \(error, privacy: .public)")
                pendingRecords.append(focus)
            }
        }
        apply(.focusComplete(focus), event: .overtimeKept)
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
            isLongBreak: focus.isLongBreak,
            breakStyle: Self.fitted(breakStyle(), length: duration),
            breakStyleFrom: 0,
            afterFocusID: focus.id
        )
        apply(.active(session), event: .breakStarted)
    }

    /// Spends the rest of this break another way, starting now. Nothing
    /// about its time changes, so nothing outside the app hears of it.
    /// Stretching needs time for a stretch at least.
    func chooseBreakStyle(_ style: BreakStyle) {
        guard var session = active, session.phase == .rest, !session.isFinished(at: now()),
              session.breakStyle != style, Self.fitted(style, length: session.remaining(at: now())) == style
        else { return }
        session.breakStyle = style
        session.breakStyleFrom = session.elapsed(at: now())
        stage = .active(session)
        persist()
    }

    /// `style`, unless it's stretching with no time for a stretch: then a rest.
    static func fitted(_ style: BreakStyle, length: TimeInterval) -> BreakStyle {
        style == .stretch && !StretchRoutine.fits(length) ? .rest : style
    }

    /// Puts a thought aside for after this focus session. Nil when there's no
    /// focus session running or nothing to park. Nothing about the session's
    /// time changes, so nothing outside the app hears of it.
    @discardableResult
    func park(_ text: String) -> ParkedThought? {
        guard var session = active, session.phase == .focus, !session.isFinished(at: now()),
              let line = ParkedThought.clean(text) else { return nil }
        let thought = ParkedThought(id: UUID(), text: line, parkedAt: now())
        session.thoughts = (session.thoughts ?? []) + [thought]
        stage = .active(session)
        persist()
        return thought
    }

    /// Plays another sound through this focus session, or none. Nothing
    /// about its time changes, so nothing outside the app hears of it.
    func setFocusSound(_ sound: FocusSound) {
        guard var session = active, session.phase == .focus,
              (session.focusSound ?? .off) != sound else { return }
        session.focusSound = sound == .off ? nil : sound
        stage = .active(session)
        persist()
    }

    /// Puts "Break's over" away: a length was chosen, so the next session is
    /// already being set up.
    func dismissBreakOver() {
        guard breakOver != nil else { return }
        breakOver = nil
        persist()
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
        if let moment = breakOver, !moment.isShowing(at: now(), calendar: calendar) { dismissBreakOver() }
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
                                       plannedSeconds: session.originalPlan, outcome: .completed,
                                       thoughts: session.thoughts)
            settleBreak(for: &focus, from: session)
            record(focus)
            apply(.focusComplete(focus), event: .focusCompleted(freshness(of: focus, at: now())))
        case .rest:
            let freshness = Freshness.of(endedAt: endedAt, now: now(), recentWindow: session.plannedDuration,
                                         calendar: calendar)
            let moment = BreakOverMoment(endedAt: endedAt, name: session.name, wasLong: session.isLongBreak == true)
            apply(.idle, event: .breakFinished(freshness),
                  breakOver: moment.isShowing(at: now(), calendar: calendar) ? moment : nil)
        }
    }

    /// Drops sessions still waiting to be saved, for "Erase all history".
    /// Otherwise the next reconcile would save them again.
    func discardAllPending() {
        guard !pendingRecords.isEmpty else { return }
        pendingRecords = []
        persist()
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

    private func apply(_ newStage: SessionStage, event: SessionEvent, breakOver: BreakOverMoment? = nil,
                       undoable: ActiveSession? = nil) {
        clearUndo()
        undoableCancel = undoable
        self.breakOver = breakOver
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
                // Update, not record: a session waiting with kept overtime
                // may already be saved without it.
                try log.update(focus)
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
        if stage == .idle { state.breakOver = breakOver }
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
