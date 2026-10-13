import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

/// Hands the widget fresh numbers and reloads it. A seam so tests don't
/// touch the App Group or WidgetCenter.
@MainActor
protocol WidgetReloading {
    func reload(with snapshot: WidgetSnapshot)
}

struct SystemWidgets: WidgetReloading {
    func reload(with snapshot: WidgetSnapshot) {
        WidgetSnapshotStore().save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// The focus-complete haptic.
@MainActor
protocol CompletionFeedback {
    func play()
}

extension CompletionHaptics: CompletionFeedback {}

/// Whether the end-of-phase alert and the Live Activity can reach the user.
enum AlertStatus: Equatable, Sendable {
    /// Not checked yet.
    case unknown
    /// Notifications haven't been asked for yet; that happens on the first Start.
    case notAsked
    case ready
    case notificationsOff
    case liveActivitiesOff
}

/// Wires the engine to its side effects: Live Activity, notifications,
/// widget reloads, the completion haptic, and VoiceOver announcements.
@MainActor
@Observable
final class AppServices: SessionEffects {
    static let shared = AppServices.live()

    let container: ModelContainer
    let engine: SessionEngine
    let calendar: Calendar
    /// True when the history store couldn't be opened. Timers still work, and
    /// finished sessions wait in the session state until it opens again.
    let historyUnavailable: Bool
    /// The most recent session event, stamped so repeats still trigger haptics.
    private(set) var lastEvent = EventStamp(event: nil, serial: 0)
    /// Bumped on each completed focus session; drives the sunburst.
    private(set) var celebrations = 0
    private(set) var alertStatus: AlertStatus = .unknown
    /// Start of the day the app shows as today. It moves at midnight, on time
    /// zone and clock changes, and on return to the foreground, so views that
    /// read it never keep showing yesterday while the app stays open.
    private(set) var today: Date
    /// What the user picked in Settings. Applies from the next session on.
    var settings: TimerSettings {
        didSet { settingsStore.save(settings) }
    }

    /// Sessions deleted from History moments ago, so they can be put back.
    /// Cleared when the undo window closes.
    private(set) var undoableDeletion: [CompletedFocus] = []

    /// The lengths a new session gets: Settings, or seconds-long test timers.
    var plan: TimerPlan {
        #if DEBUG
        if DevSettings.shared.shortTimers { return settings.plan.asTestTimers() }
        #endif
        return settings.plan
    }

    @ObservationIgnored private let liveActivity: LiveActivityControlling
    @ObservationIgnored private let notifications: EndNotifying
    @ObservationIgnored private let widgets: WidgetReloading
    @ObservationIgnored private let haptics: CompletionFeedback
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let settingsStore: SettingsStoring
    /// Low Power Mode and heat: when set, decoration stops.
    let power: PowerState
    /// The bedside clock, shared by the Focus screen and Settings.
    let bedside: BedsideController
    /// Nil when the store couldn't be opened: History can't be changed then.
    @ObservationIgnored let history: HistoryService?
    @ObservationIgnored private let schedulesTimers: Bool
    @ObservationIgnored private var deletionExpiry: Task<Void, Never>?
    @ObservationIgnored private var timeObservers: [NSObjectProtocol] = []

    init(container: ModelContainer,
         historyUnavailable: Bool = false,
         stateStore: SessionStateStoring,
         settingsStore: SettingsStoring = InMemorySettingsStore(),
         power: PowerState? = nil,
         orientation: OrientationRequesting = SystemOrientation(),
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .autoupdatingCurrent,
         schedulesCompletion: Bool = true,
         liveActivity: LiveActivityControlling,
         notifications: EndNotifying,
         widgets: WidgetReloading,
         haptics: CompletionFeedback,
         announce: @escaping @MainActor (String) -> Void) {
        self.container = container
        self.historyUnavailable = historyUnavailable
        self.liveActivity = liveActivity
        self.notifications = notifications
        self.widgets = widgets
        self.haptics = haptics
        self.announce = announce
        self.calendar = calendar
        self.settingsStore = settingsStore
        self.power = power ?? PowerState(read: { false })
        bedside = BedsideController(orientation: orientation)
        self.schedulesTimers = schedulesCompletion
        history = historyUnavailable ? nil : HistoryService(container: container)
        settings = settingsStore.load()
        today = calendar.startOfDay(for: now())
        let log: FocusLogging = historyUnavailable ? UnavailableFocusLog() : SwiftDataFocusLog(container: container)
        engine = SessionEngine(now: now, calendar: calendar, store: stateStore, log: log,
                               schedulesCompletion: schedulesCompletion)
        engine.effects = self
        engine.plan = { [weak self] in self?.plan ?? .classic }
    }

    /// The real thing: the App Group store, ActivityKit, notifications, haptics.
    static func live() -> AppServices {
        var historyUnavailable = false
        let container: ModelContainer
        do {
            container = try SharedStore.makeModelContainer()
        } catch {
            Log.store.fault("Couldn't open the history store; History is unavailable this launch: \(error, privacy: .public)")
            historyUnavailable = true
            container = makeEmptyContainer()
        }
        let services = AppServices(container: container, historyUnavailable: historyUnavailable,
                                   stateStore: DefaultsSessionStateStore(), settingsStore: DefaultsSettingsStore(),
                                   power: PowerState(),
                                   liveActivity: LiveActivityController(), notifications: EndNotifier(),
                                   widgets: SystemWidgets(), haptics: CompletionHaptics(),
                                   announce: { AccessibilityNotification.Announcement($0).post() })
        IntentBridge.setPaused = { [weak services] paused, sessionID in
            await services?.lockScreenSetPaused(paused, sessionID: sessionID)
        }
        services.engine.undoWindow = {
            // Reaching Undo takes longer with a screen reader or switches.
            UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
                ? 30 : SessionEngine.standardUndoWindow
        }
        services.observeTimeChanges()
        services.power.observe()
        return services
    }

    /// Midnight, time zone and DST changes, and the clock being set. These
    /// arrive while the app runs; a suspended app catches up on `reconcile()`.
    private func observeTimeChanges() {
        let names: [Notification.Name] = [UIApplication.significantTimeChangeNotification, .NSCalendarDayChanged,
                                           .NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
        timeObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.timeChanged() }
            }
        }
    }

    /// An empty in-memory store, for the UI when the real one won't open, and for previews.
    static func makeEmptyContainer() -> ModelContainer {
        do {
            return try SharedStore.makeModelContainer(inMemory: true)
        } catch {
            fatalError("An in-memory store only fails if the model itself is broken: \(error)")
        }
    }

    // MARK: Effects

    func sessionEngine(_ engine: SessionEngine, didEmit event: SessionEvent) {
        switch event {
        case .started, .resumed, .breakStarted, .restored, .extended:
            if let session = engine.active {
                syncLiveActivity(session)
                notifications.schedule(for: session)
            }
        case .paused:
            if let session = engine.active { syncLiveActivity(session) }
            notifications.cancel()
        case .cancelled:
            liveActivity.endAll()
            notifications.cancel()
            announce(String(localized: "Session cancelled. Undo is available for a few seconds."))
        case .breakSkipped, .completionDismissed:
            liveActivity.endAll()
            notifications.cancel()
        case .focusCompleted(let freshness):
            // Found long after the fact, it opens quietly: no ding, no sunburst,
            // and no "done" card left behind on the Lock Screen.
            let celebrates = freshness != .stale
            let breakLength = engine.stage.completedFocus.map(engine.breakLength(after:)) ?? plan.shortBreak
            liveActivity.showFocusDone(completedToday: completedToday, breakDuration: breakLength, lingers: celebrates)
            if celebrates {
                haptics.play()
                celebrations += 1
            }
            clearLateAlert(freshness)
            if freshness == .live {
                announce("\(Copy.focusComplete). \(Copy.breakLine(seconds: breakLength))")
            }
        case .finishedEarly:
            // Finished by hand in the app: no alert to come, no ding, and
            // no card left on the Lock Screen.
            notifications.cancel()
            let breakLength = engine.stage.completedFocus.map(engine.breakLength(after:)) ?? plan.shortBreak
            liveActivity.showFocusDone(completedToday: completedToday, breakDuration: breakLength, lingers: false)
            announce("\(Copy.endedEarly). \(Copy.breakLine(seconds: breakLength))")
        case .breakFinished(let freshness):
            liveActivity.endAll()
            clearLateAlert(freshness)
            if freshness == .live { announce("\(Copy.breakOver). \(Copy.readyWhenYouAre)") }
        case .historySaved:
            break // The widget refresh below picks up the newly saved sessions.
        }
        lastEvent = EventStamp(event: event, serial: lastEvent.serial + 1)
        refreshWidgets()
    }

    // MARK: History changes

    /// Deletes sessions from History. They can be put back with `undoDelete`
    /// for a few seconds (longer with assistive technologies).
    func deleteSessions(_ ids: Set<UUID>) {
        guard let history, !ids.isEmpty else { return }
        do {
            undoableDeletion = try history.delete(ids: ids)
        } catch {
            Log.store.error("Couldn't delete sessions: \(error, privacy: .public)")
            return
        }
        historyChanged()
        announce(String(localized: "Session deleted. Undo is available for a few seconds."))
        let window = engine.undoWindow()
        deletionExpiry?.cancel()
        guard schedulesTimers else { return }
        deletionExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            self?.undoableDeletion = []
        }
    }

    func undoDelete() {
        guard let history, !undoableDeletion.isEmpty else { return }
        do {
            try history.restore(undoableDeletion)
        } catch {
            Log.store.error("Couldn't put deleted sessions back: \(error, privacy: .public)")
            return
        }
        clearUndoableDeletion()
        historyChanged()
    }

    func renameSession(_ id: UUID, to name: String) {
        do {
            try history?.rename(id: id, to: name)
        } catch {
            Log.store.error("Couldn't rename a session: \(error, privacy: .public)")
        }
    }

    /// Deletes every saved session, and any still waiting to be saved.
    func eraseHistory() {
        guard let history else { return }
        do {
            try history.deleteAll()
        } catch {
            Log.store.error("Couldn't erase History: \(error, privacy: .public)")
            return
        }
        engine.discardAllPending()
        clearUndoableDeletion()
        historyChanged()
    }

    /// What restoring `data` would change. Nothing is saved yet.
    func planImport(of data: Data) throws -> HistoryExport.ImportPlan {
        guard let history else { throw HistoryExport.ImportError.unreadable }
        let backup = try HistoryExport.readBackup(data)
        let existing = try history.sessions(ids: Set(backup.sessions.map(\.id)))
        return HistoryExport.plan(backup, existing: existing, now: engine.now())
    }

    /// Saves a restore worked out by `planImport`, all at once.
    func importSessions(_ plan: HistoryExport.ImportPlan) throws {
        guard let history else { return }
        try history.upsert(plan.changes)
        clearUndoableDeletion()
        historyChanged()
    }

    /// Redraws today's totals wherever they show outside the app.
    func historyChanged() {
        if let session = engine.active { syncLiveActivity(session) }
        refreshWidgets()
    }

    private func clearUndoableDeletion() {
        deletionExpiry?.cancel()
        deletionExpiry = nil
        undoableDeletion = []
    }

    // MARK: Lifecycle

    /// Restores the engine at launch, then clears anything it no longer explains.
    func restore() {
        engine.restore()
        endOrphanedActivities()
        refreshWidgets()
    }

    /// Catches up after returning to the foreground, including a day that
    /// turned over while the app was suspended.
    func reconcile() {
        engine.reconcile()
        endOrphanedActivities()
        if refreshToday() { resyncSurfaces() }
    }

    /// The clock, time zone or day changed under a running app. Catches the
    /// session up, re-aims the end alert (it counts elapsed time while the
    /// session counts wall-clock time), and redraws today's totals everywhere.
    func timeChanged() {
        refreshToday()
        engine.reconcile()
        endOrphanedActivities()
        resyncSurfaces()
    }

    /// The Lock Screen pause button. If it changes nothing (a second tap, or
    /// a card that's out of date) the card is redrawn to match the timer.
    func lockScreenSetPaused(_ paused: Bool?, sessionID: UUID?) async {
        let before = engine.stage
        if let paused {
            engine.setPaused(paused, sessionID: sessionID)
        } else {
            engine.togglePause()
        }
        if engine.stage == before {
            if let session = engine.active { syncLiveActivity(session) } else { endOrphanedActivities() }
        }
        await settle()
    }

    /// When idle nothing should be on the Lock Screen or in the Dynamic Island,
    /// e.g. a card left by a session that ended while the app wasn't running.
    /// `endAll` lists activities off the main actor, so this is cheap when there are none.
    private func endOrphanedActivities() {
        if engine.stage == .idle { liveActivity.endAll() }
    }

    /// Waits for side effects still in flight: the end alert and Live Activity
    /// updates. Intents that run while the app is in the background await this
    /// so the system doesn't suspend the app before they land.
    func settle() async {
        await notifications.flush()
        await liveActivity.flush()
    }

    /// Re-reads whether alerts and Live Activities are allowed. Called at launch
    /// and on every return to the foreground, which covers coming back from the
    /// permission prompt or from Settings.
    func refreshAlertStatus() async {
        let notificationStatus = await notifications.authorizationStatus()
        let activitiesEnabled = await liveActivity.areActivitiesEnabled()
        alertStatus = switch notificationStatus {
        case .notDetermined: .notAsked
        case .denied: .notificationsOff
        default: activitiesEnabled ? .ready : .liveActivitiesOff
        }
    }

    /// An ending found after the fact has already been alerted, or, after the
    /// clock jumped forward, would be alerted late. Either way the alert is
    /// stale. A live ending's alert is playing right now, so it stays.
    private func clearLateAlert(_ freshness: Freshness) {
        if freshness != .live { notifications.cancel() }
    }

    /// Moves `today` to the current day. True if it changed.
    @discardableResult
    private func refreshToday() -> Bool {
        let start = calendar.startOfDay(for: engine.now())
        guard start != today else { return false }
        today = start
        return true
    }

    /// Re-sends the session to the Lock Screen and the end alert, and the day's totals to the widget.
    private func resyncSurfaces() {
        if let session = engine.active {
            syncLiveActivity(session)
            notifications.schedule(for: session)
        }
        refreshWidgets()
    }

    private func syncLiveActivity(_ session: ActiveSession) {
        liveActivity.sync(with: session, completedToday: completedToday,
                          breakDuration: session.nextBreakSeconds ?? plan.shortBreak)
    }

    private func refreshWidgets() {
        widgets.reload(with: WidgetSnapshot(rows: todayRows(), writtenAt: engine.now()))
    }

    /// Focus sessions finished today, saved or waiting.
    private func todayRows() -> [FocusRow] {
        let now = engine.now()
        let saved = TodayStats.fetchRecords(on: now, calendar: calendar, context: container.mainContext)
        return TodayStats.rows(saved: saved.map(\.row), pending: engine.pendingRecords(on: now))
    }

    /// For the pills on the Lock Screen.
    private var completedToday: Int { todayRows().fullCount }

    #if DEBUG
    /// In memory and without side effects, so previews never touch real data.
    static let preview = AppServices(container: makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                                     liveActivity: SilentEffects(), notifications: SilentEffects(),
                                     widgets: SilentEffects(), haptics: SilentEffects(), announce: { _ in })

    /// Replays an event's feedback without touching the session: its haptic,
    /// and for a completion the "ding" pattern and the sunburst.
    func debugReplay(_ event: SessionEvent) {
        if case .focusCompleted = event {
            haptics.play()
            celebrations += 1
        }
        lastEvent = EventStamp(event: event, serial: lastEvent.serial + 1)
    }
    #endif
}

#if DEBUG
/// Does nothing, for previews.
@MainActor
private final class SilentEffects: LiveActivityControlling, EndNotifying, WidgetReloading, CompletionFeedback {
    func sync(with session: ActiveSession, completedToday: Int, breakDuration: TimeInterval) {}
    func showFocusDone(completedToday: Int, breakDuration: TimeInterval, lingers: Bool) {}
    func endAll() {}
    func areActivitiesEnabled() async -> Bool { true }
    func flush() async {}
    func schedule(for session: ActiveSession) {}
    func cancel() {}
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func reload(with snapshot: WidgetSnapshot) {}
    func play() {}
}
#endif

struct EventStamp: Equatable {
    var event: SessionEvent?
    var serial: Int

    /// Light-touch feedback for each transition. Focus completion uses the
    /// custom Core Haptics pattern instead.
    var feedback: SensoryFeedback? {
        switch event {
        case .started: .impact(weight: .medium, intensity: 0.8)
        case .paused, .resumed, .extended: .selection
        case .finishedEarly: .impact(weight: .medium, intensity: 0.6)
        case .cancelled: .warning
        case .breakStarted: .impact(flexibility: .soft, intensity: 0.7)
        case .breakSkipped: .impact(weight: .light)
        case .breakFinished(let freshness): freshness == .stale ? nil : .success
        case .focusCompleted, .completionDismissed, .restored, .historySaved, nil: nil
        }
    }
}
