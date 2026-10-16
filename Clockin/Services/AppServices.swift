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
        ControlCenter.shared.reloadControls(ofKind: ControlFace.kind)
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
    /// "Ring when time's up" is on, but Clockin may not ring alarms.
    case alarmsOff
}

/// A History change that can be undone for a few seconds.
enum HistoryUndo: Equatable {
    case deletion([CompletedFocus])
    case rename(SubjectRename)
    /// Thoughts ticked off or cleared, with the book as it was.
    case thoughts(ThoughtBook, cleared: Bool)
}

/// What "Rename everywhere" changed, to put back.
struct SubjectRename: Equatable {
    /// The new name, for the undo bar.
    var name: String
    /// Saved sessions' old names, by id.
    var records: [UUID: String]
    var engine: SessionEngine.NameChanges
    /// The two names' symbol picks before, by key.
    var symbols: [String: String?]
    var plan: SetPlan?
    var field: String
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
    /// The end alarm is ringing right now.
    private(set) var alarmRinging = false
    /// Start of the day the app shows as today. It moves at midnight, on time
    /// zone and clock changes, and on return to the foreground, so views that
    /// read it never keep showing yesterday while the app stays open.
    private(set) var today: Date
    /// What the user picked in Settings. Applies from the next session on.
    var settings: TimerSettings {
        didSet {
            settingsStore.save(settings)
            if settings.focusSoundVolume != oldValue.focusSoundVolume || settings.mixFocusSound != oldValue.mixFocusSound {
                focusSound.configure(volume: settings.focusSoundVolume, mixes: settings.mixFocusSound)
            }
        }
    }

    /// The focus session's sound, following the session.
    @ObservationIgnored let focusSound: any FocusSoundPlaying

    /// Thoughts parked in finished sessions, and unfiled ones from cancelled sessions.
    private(set) var thoughts: ThoughtBook {
        didSet { if thoughts != oldValue { thoughtStore.save(thoughts) } }
    }
    @ObservationIgnored private let thoughtStore: ThoughtStoring

    /// The symbol picked for each session name.
    private(set) var symbolBook: SymbolBook {
        didSet { if symbolBook != oldValue { symbolStore.save(symbolBook) } }
    }

    /// The optional plan for today's set. Dropped quietly when the day moves on.
    private(set) var plannedSet: SetPlan? {
        didSet { if plannedSet != oldValue { planStore.save(plannedSet) } }
    }
    @ObservationIgnored private let planStore: SetPlanStoring
    /// The slot whose name just went into the name field when a session
    /// finished, for the Focus screen to show it moving there. Cleared once shown.
    var planHandoff: UUID?

    /// The History change made moments ago that can still be undone: the
    /// newest only, as one bar shows it. Cleared when the undo window closes.
    private(set) var historyUndo: HistoryUndo?

    /// Sessions deleted from History moments ago, so they can be put back.
    var undoableDeletion: [CompletedFocus] {
        if case .deletion(let sessions)? = historyUndo { return sessions }
        return []
    }

    /// The lengths a new session gets: Settings, or seconds-long test timers.
    var plan: TimerPlan {
        #if DEBUG
        if DevSettings.shared.shortTimers { return settings.plan.asTestTimers() }
        #endif
        return settings.plan
    }

    @ObservationIgnored private let liveActivity: LiveActivityControlling
    @ObservationIgnored private let notifications: EndNotifying
    @ObservationIgnored private let alarm: EndAlarming
    @ObservationIgnored private let mindful: MindfulLogging
    @ObservationIgnored private let appIcon: AppIconSwitching
    /// The Home Screen icon chosen in Settings.
    private(set) var appIconChoice: AppIconChoice
    @ObservationIgnored private let widgets: WidgetReloading
    @ObservationIgnored private let haptics: CompletionFeedback
    @ObservationIgnored private let sounds: TimerSounds
    /// Whether the app is on screen: timer sounds play only then.
    @ObservationIgnored private let isForeground: @MainActor () -> Bool
    /// Above 0 while Siri, Shortcuts, the control or a Lock Screen or alarm
    /// button is acting: those changes make no sound.
    @ObservationIgnored private var soundsMuted = 0
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let settingsStore: SettingsStoring
    @ObservationIgnored private let symbolStore: SymbolBookStoring
    /// Low Power Mode and heat: when set, decoration stops.
    let power: PowerState
    /// Writes History's week line on the device, when Apple Intelligence can.
    var weekWriter: any WeekSentenceWriting = OnDeviceWeekWriter()
    /// The bedside clock, shared by the Focus screen and Settings.
    let bedside: BedsideController
    /// Nil when the store couldn't be opened: History can't be changed then.
    @ObservationIgnored let history: HistoryService?
    @ObservationIgnored private let schedulesTimers: Bool
    @ObservationIgnored private var historyUndoExpiry: Task<Void, Never>?
    @ObservationIgnored private var extendOffer: Task<Void, Never>?
    @ObservationIgnored private var timeObservers: [NSObjectProtocol] = []

    init(container: ModelContainer,
         historyUnavailable: Bool = false,
         stateStore: SessionStateStoring,
         settingsStore: SettingsStoring = InMemorySettingsStore(),
         symbolStore: SymbolBookStoring = InMemorySymbolBookStore(),
         thoughtStore: ThoughtStoring = InMemoryThoughtStore(),
         planStore: SetPlanStoring = InMemorySetPlanStore(),
         power: PowerState? = nil,
         orientation: OrientationRequesting = SystemOrientation(),
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .autoupdatingCurrent,
         schedulesCompletion: Bool = true,
         liveActivity: LiveActivityControlling,
         notifications: EndNotifying,
         alarm: EndAlarming = NoAlarm(),
         mindful: MindfulLogging = NoMindfulLog(),
         appIcon: AppIconSwitching = SystemAppIcon(),
         widgets: WidgetReloading,
         haptics: CompletionFeedback,
         sounds: TimerSounds = NoSounds(),
         focusSound: any FocusSoundPlaying = NoFocusSound(),
         isForeground: @escaping @MainActor () -> Bool = { true },
         announce: @escaping @MainActor (String) -> Void) {
        self.container = container
        self.historyUnavailable = historyUnavailable
        self.liveActivity = liveActivity
        self.notifications = notifications
        self.alarm = alarm
        self.mindful = mindful
        self.appIcon = appIcon
        appIconChoice = appIcon.current
        self.widgets = widgets
        self.haptics = haptics
        self.sounds = sounds
        self.focusSound = focusSound
        self.isForeground = isForeground
        self.announce = announce
        self.calendar = calendar
        self.settingsStore = settingsStore
        self.symbolStore = symbolStore
        self.thoughtStore = thoughtStore
        self.planStore = planStore
        self.power = power ?? PowerState(read: { false })
        bedside = BedsideController(orientation: orientation)
        self.schedulesTimers = schedulesCompletion
        history = historyUnavailable ? nil : HistoryService(container: container)
        settings = settingsStore.load()
        symbolBook = symbolStore.load()
        thoughts = thoughtStore.load()
        today = calendar.startOfDay(for: now())
        plannedSet = planStore.load()
        let log: FocusLogging = historyUnavailable ? UnavailableFocusLog() : SwiftDataFocusLog(container: container)
        engine = SessionEngine(now: now, calendar: calendar, store: stateStore, log: log,
                               schedulesCompletion: schedulesCompletion)
        engine.effects = self
        engine.plan = { [weak self] in self?.plan ?? .classic }
        engine.breakStyle = { [weak self] in self?.settings.duringBreaks ?? .rest }
        engine.focusSound = { [weak self] in self?.settings.focusSound ?? .off }
        focusSound.configure(volume: settings.focusSoundVolume, mixes: settings.mixFocusSound)
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
                                   symbolStore: DefaultsSymbolBookStore(), thoughtStore: FileThoughtStore(),
                                   planStore: DefaultsSetPlanStore(),
                                   power: PowerState(),
                                   liveActivity: LiveActivityController(), notifications: EndNotifier(),
                                   alarm: EndAlarm(), mindful: MindfulMinutes(), widgets: SystemWidgets(),
                                   haptics: CompletionHaptics(), sounds: SystemTimerSounds(),
                                   focusSound: FocusSoundPlayer(),
                                   isForeground: { UIApplication.shared.applicationState == .active },
                                   announce: { AccessibilityNotification.Announcement($0).post() })
        IntentBridge.setPaused = { [weak services] paused, sessionID in
            await services?.lockScreenSetPaused(paused, sessionID: sessionID)
        }
        IntentBridge.startBreak = { [weak services] sessionID in
            await services?.alarmStartBreak(after: sessionID)
        }
        IntentBridge.startFocus = { [weak services] minutes, name in
            await services?.intentStart(minutes: minutes, name: name) ?? .nothingRunning
        }
        IntentBridge.pauseFocus = { [weak services] in await services?.intentPause() ?? .nothingRunning }
        IntentBridge.resumeFocus = { [weak services] in await services?.intentResume() ?? .nothingRunning }
        IntentBridge.stopFocus = { [weak services] in await services?.intentStop() ?? .nothingRunning }
        IntentBridge.primaryAction = { [weak services] in await services?.intentPrimary() ?? .nothingRunning }
        IntentBridge.parkThought = { [weak services] text in await services?.intentPark(text) ?? .nowhereToPark }
        IntentBridge.extendFocus = { [weak services] sessionID in await services?.lockScreenExtend(sessionID: sessionID) }
        services.engine.undoWindow = {
            // Reaching Undo takes longer with a screen reader or switches.
            UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
                ? 30 : SessionEngine.standardUndoWindow
        }
        services.observeTimeChanges()
        services.power.observe()
        services.watchAlarm()
        return services
    }

    /// Follows whether the end alarm is ringing, for Tick.
    func watchAlarm() {
        alarm.watchRinging { [weak self] ringing in self?.alarmRinging = ringing }
    }

    /// Stops the ringing alarm (Tick tapped while it rings).
    func stopAlarm() {
        guard alarmRinging else { return }
        alarm.cancel()
        alarmRinging = false
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
        if let sound = TimerSound.for(event) { playSound(sound) }
        if let fade = FocusSoundFade.for(event) { focusSound.follow(focusSoundCue, fade: fade, chosen: false) }
        keepThoughts(after: event)
        tickPlan(after: event)
        noteForTips(event)
        switch event {
        case .started, .resumed, .breakStarted, .restored, .extended:
            if let session = engine.active {
                syncLiveActivity(session)
                scheduleEndAlert(for: session)
            }
        case .paused:
            if let session = engine.active { syncLiveActivity(session) }
            cancelEndAlert()
        case .breakStyleChanged:
            // Only the card's words change; the alert still rings at the same time.
            if let session = engine.active { syncLiveActivity(session) }
        case .cancelled:
            liveActivity.endAll()
            cancelEndAlert()
            announce(String(localized: "Session cancelled. Undo is available for a few seconds."))
        case .breakSkipped:
            liveActivity.endAll()
            cancelEndAlert()
            announce(String(localized: "Break skipped. Undo is available for a few seconds."))
        case .completionDismissed:
            liveActivity.endAll()
            cancelEndAlert()
            announce(String(localized: "No break this time. Undo is available for a few seconds."))
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
            saveFinishedToHealth()
        case .finishedEarly:
            // Finished by hand in the app: no alert to come, no ding, and
            // no card left on the Lock Screen.
            cancelEndAlert()
            let breakLength = engine.stage.completedFocus.map(engine.breakLength(after:)) ?? plan.shortBreak
            liveActivity.showFocusDone(completedToday: completedToday, breakDuration: breakLength, lingers: false)
            announce("\(Copy.endedEarly). \(Copy.breakLine(seconds: breakLength))")
            saveFinishedToHealth()
        case .breakFinished(let freshness):
            // Just over: the card says so, with Start focus. Long after: gone.
            if freshness != .stale, engine.breakOver != nil { liveActivity.showBreakDone() } else { liveActivity.endAll() }
            clearLateAlert(freshness)
            if freshness == .live { announce("\(Copy.breakOver). \(Copy.readyWhenYouAre)") }
        case .breakOverEnded:
            // Back to plain waiting: the Lock Screen's "Break's over" goes too.
            liveActivity.endAll()
        case .overtimeKept:
            saveFinishedToHealth()
        case .historySaved:
            break // The widget refresh below picks up the saved sessions' new totals.
        }
        lastEvent = EventStamp(event: event, serial: lastEvent.serial + 1)
        refreshWidgets()
    }

    // MARK: Quick actions

    /// Refreshes the Home Screen icon's quick actions for what's going on now.
    func refreshQuickActions() {
        let recent = (try? history?.recentNames(limit: 3)) ?? []
        let actions = QuickAction.available(focusing: engine.active?.phase == .focus, next: nextPlanned?.name,
                                            recentNames: recent)
        UIApplication.shared.shortcutItems = actions.map { $0.shortcutItem(symbol: symbol(for:)) }
    }

    /// Does what a quick action asks. Starting from the icon is in the app,
    /// on screen: it winds up as usual.
    func perform(_ action: QuickAction) {
        engine.reconcile()
        switch action {
        case .start(let name):
            guard !engine.hasActiveSession else { break }
            // The field follows, so the screen and what's next agree.
            setLastSessionName(name)
            engine.start(name: name)
        case .pause:
            engine.pause()
        case .park:
            parkFieldOpen = engine.active?.phase == .focus
        case .history:
            break
        }
    }

    // MARK: Tips

    /// What the hints wait on: no tip during focus or before a first finish.
    private func noteForTips(_ event: SessionEvent) {
        ClockinTips.focusRunning = engine.active?.phase == .focus
        switch event {
        case .started: ClockinTips.note(ClockinTips.sessionStarted)
        case .breakStarted: ClockinTips.note(ClockinTips.breakStarted)
        case .focusCompleted, .finishedEarly: ClockinTips.hasFinished = true
        default: break
        }
    }

    // MARK: Parked thoughts

    /// The park field is open on the Focus screen (from the chip, a link or a quick action).
    var parkFieldOpen = false
    /// When the last thought parked in the app reaches Tick, for the catch.
    private(set) var lastCatch: Date?
    /// Where Tick is on screen, in global space: where a parked thought flies to.
    @ObservationIgnored var tickFrame: CGRect = .zero

    /// Puts a thought aside during focus. False when there's no focus
    /// session running, or nothing but spaces.
    @discardableResult
    func park(_ text: String) -> Bool {
        guard engine.park(text) != nil else { return false }
        ClockinTips.note(ClockinTips.thoughtParked)
        return true
    }

    /// Parked from the field: said aloud for VoiceOver; the screen sends it to Tick.
    func parkFromField(_ text: String) -> Bool {
        guard park(text) else { return false }
        announce(Copy.thoughtParked)
        return true
    }

    /// Tick catches a thought arriving at `date`.
    func catchThought(at date: Date) { lastCatch = date }

    /// The thoughts to show after focus: the finished session's, then the
    /// break's session's, kept or still on the session.
    var thoughtsAfterFocus: (session: UUID, thoughts: [ParkedThought])? {
        switch engine.stage {
        case .focusComplete(let focus):
            return (focus.id, thoughts.bySession[focus.id] ?? focus.thoughts ?? [])
        case .active(let session) where session.phase == .rest:
            guard let id = session.afterFocusID else { return nil }
            return (id, thoughts.thoughts(for: id))
        default:
            return nil
        }
    }

    func setThoughtDone(_ done: Bool, _ id: UUID) { thoughts.setDone(done, thought: id) }

    func clearThoughts(of session: UUID) { thoughts.clear(session: session) }

    func clearUnfiledThoughts() { thoughts.clearUnfiled() }

    /// Ticked off in History's open thoughts: Undo brings it back.
    func tickOffThought(_ id: UUID) {
        let before = thoughts
        thoughts.setDone(true, thought: id)
        guard thoughts != before else { return }
        settleHistoryUndo()
        historyUndo = .thoughts(before, cleared: false)
        openHistoryUndoWindow()
    }

    /// Forgets the thoughts already ticked off, with Undo.
    func clearTickedThoughts() {
        let before = thoughts
        thoughts.clearDone()
        guard thoughts != before else { return }
        settleHistoryUndo()
        historyUndo = .thoughts(before, cleared: true)
        announce(String(localized: "Ticked thoughts cleared. Undo is available for a few seconds."))
        openHistoryUndoWindow()
    }

    /// The thoughts still open, by subject, with the cancelled sessions'
    /// last. Sessions waiting in a delete's Undo are left out; `keeping`
    /// are ticked off but still folding away.
    func openThoughts(keeping: Set<UUID> = []) -> OpenThoughts {
        let filed = Set(thoughts.bySession.keys)
        var names: [UUID: String] = [:]
        if !filed.isEmpty, let saved = try? history?.sessions(ids: filed) {
            for (id, focus) in saved { names[id] = focus.name }
        }
        for focus in engine.pendingRecords where filed.contains(focus.id) { names[focus.id] = focus.name }
        if let focus = engine.stage.completedFocus { names[focus.id] = focus.name }
        let hidden = Set(undoableDeletion.map(\.id))
        return OpenThoughts(book: thoughts, names: names.filter { !hidden.contains($0.key) }, keeping: keeping)
    }

    #if DEBUG
    /// `-DemoData`: thoughts kept with demo sessions.
    func seedThoughts(_ book: ThoughtBook) { thoughts.merge(book) }
    #endif

    /// Keeps thoughts with their session when it finishes, and unfiled when
    /// it's cancelled, so none is lost; Undo puts them back on the session.
    private func keepThoughts(after event: SessionEvent) {
        switch event {
        case .focusCompleted, .finishedEarly:
            if let focus = engine.stage.completedFocus, let parked = focus.thoughts {
                thoughts.file(parked, under: focus.id)
            }
        case .cancelled:
            if let parked = engine.undoableCancel?.thoughts { thoughts.unfile(parked) }
        case .restored:
            if let parked = engine.active?.thoughts { thoughts.takeBack(Set(parked.map(\.id))) }
        default:
            break
        }
    }

    /// Forgets thoughts kept for sessions no longer in History, nor waiting to be.
    func pruneThoughts() {
        guard let history, !thoughts.bySession.isEmpty else { return }
        do {
            var keep = Set(try history.sessions(ids: Set(thoughts.bySession.keys)).keys)
            keep.formUnion(engine.pendingRecords.map(\.id))
            keep.formUnion(undoableDeletion.map(\.id))
            if let focus = engine.stage.completedFocus { keep.insert(focus.id) }
            if let after = engine.active?.afterFocusID { keep.insert(after) }
            thoughts.prune(keeping: keep)
        } catch {
            Log.store.error("Couldn't read sessions to tidy parked thoughts: \(error, privacy: .public)")
        }
    }

    // MARK: Today's plan

    /// The plan, if it's today's.
    var todaysSet: SetPlan? {
        guard let plannedSet, plannedSet.isFor(day: today, calendar: calendar) else { return nil }
        return plannedSet
    }

    /// The next planned session, if there's a plan with one still to do.
    var nextPlanned: SetPlan.Slot? { todaysSet?.next }

    /// The next planned session with its symbol, for the Lock Screen and the widget.
    var nextUp: NextUp? { nextPlanned.map { NextUp(name: $0.name, symbol: symbol(for: $0.name)) } }

    /// What comes after a session called `name`: the next planned one, or the same again.
    func nextName(after name: String) -> String { nextPlanned?.name ?? name }

    /// The plan sheet's changes. An empty plan is no plan.
    func editSet(_ plan: SetPlan?) {
        let edited = plan.flatMap { $0.isEmpty ? nil : $0 }
        guard edited != plannedSet else { return }
        plannedSet = edited
        planChanged()
    }

    /// "Next" is said in more places than the app: the Lock Screen during a
    /// break, the break's alert and the widget.
    private func planChanged() {
        resyncSurfaces()
    }

    /// A finished focus session ticks its planned slot, on the day it
    /// finished, and puts the next planned name in the field.
    private func tickPlan(after event: SessionEvent) {
        switch event {
        case .focusCompleted, .finishedEarly: break
        default: return
        }
        guard let focus = engine.stage.completedFocus, var plan = plannedSet,
              plan.isFor(day: focus.completedAt, calendar: calendar),
              plan.finish(name: focus.name, session: focus.id) else { return }
        plannedSet = plan
        if let next = plan.next {
            setLastSessionName(next.name)
            planHandoff = next.id
        }
    }

    /// Yesterday's plan goes without a word.
    private func dropStalePlan() {
        if let plannedSet, !plannedSet.isFor(day: today, calendar: calendar) { self.plannedSet = nil }
    }

    // MARK: Focus sound

    /// What should be playing now: the running focus session's sound, if it has one.
    var focusSoundCue: FocusSoundCue? {
        guard let session = engine.active, session.phase == .focus, let end = session.endDate,
              let sound = session.focusSound, sound != .off else { return nil }
        return FocusSoundCue(sound: sound, bell: end)
    }

    /// Picked on the session chip: plays through this session, and is
    /// remembered for the next one.
    func chooseFocusSound(_ sound: FocusSound) {
        engine.setFocusSound(sound)
        settings.focusSound = sound
        focusSound.follow(focusSoundCue, fade: sound == .off ? .stopOut : .resumeIn, chosen: true)
    }

    // MARK: Sounds

    /// One detent of the dial while the knob is dragged.
    func playRatchet() {
        playSound(.ratchet)
    }

    /// Only for a change made in the app, on screen, with sounds on.
    private func playSound(_ sound: TimerSound) {
        guard settings.timerSounds, soundsMuted == 0, isForeground() else { return }
        sounds.play(sound)
    }

    /// Runs a change made from outside the app (Siri, Shortcuts, the control,
    /// a Lock Screen or alarm button) without its sound.
    private func withoutSounds<T>(_ body: () async -> T) async -> T {
        soundsMuted += 1
        defer { soundsMuted -= 1 }
        return await body()
    }

    // MARK: History changes

    /// Deletes sessions from History. They can be put back with `undoDelete`
    /// for a few seconds (longer with assistive technologies).
    func deleteSessions(_ ids: Set<UUID>) {
        guard let history, !ids.isEmpty else { return }
        let removed: [CompletedFocus]
        do {
            removed = try history.delete(ids: ids)
        } catch {
            Log.store.error("Couldn't delete sessions: \(error, privacy: .public)")
            return
        }
        settleHistoryUndo()
        historyUndo = .deletion(removed)
        if writesHealth { mindful.remove(ids: Array(ids)) }
        historyChanged()
        announce(String(localized: "Session deleted. Undo is available for a few seconds."))
        openHistoryUndoWindow()
    }

    /// Undo stays on offer for a few seconds (longer with assistive technologies).
    private func openHistoryUndoWindow() {
        let window = engine.undoWindow()
        historyUndoExpiry?.cancel()
        guard schedulesTimers else { return }
        historyUndoExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            self?.expireHistoryUndo()
        }
    }

    /// Undo has run out: the change stands.
    func expireHistoryUndo() {
        switch historyUndo {
        case .deletion: expireDeletion()
        case .rename, .thoughts: historyUndo = nil
        case nil: break
        }
    }

    /// A newer change takes the undo bar: the one before stands now.
    private func settleHistoryUndo() {
        historyUndoExpiry?.cancel()
        historyUndoExpiry = nil
        expireHistoryUndo()
    }

    /// Puts back whatever the bar offers.
    func undoHistoryChange() {
        switch historyUndo {
        case .deletion: undoDelete()
        case .rename(let rename): undoRename(rename)
        case .thoughts(let book, _):
            clearUndoableDeletion()
            thoughts = book
        case nil: break
        }
    }

    /// Undo for a delete has run out: what's gone stays gone, with its
    /// symbols and parked thoughts.
    func expireDeletion() {
        guard case .deletion(let removed)? = historyUndo else { return }
        let gone = Set(removed.map(\.id))
        historyUndo = nil
        // A planned slot those sessions ticked is to do again.
        if var plan = plannedSet, !gone.isEmpty {
            plan.reopen(sessions: gone)
            if plan != plannedSet {
                plannedSet = plan
                planChanged()
            }
        }
        pruneSymbols()
        pruneThoughts()
    }

    func undoDelete() {
        guard let history, !undoableDeletion.isEmpty else { return }
        let removed = undoableDeletion
        do {
            try history.restore(removed)
        } catch {
            Log.store.error("Couldn't put deleted sessions back: \(error, privacy: .public)")
            return
        }
        if writesHealth { removed.forEach(mindful.save) }
        clearUndoableDeletion()
        historyChanged()
    }

    // MARK: Rename everywhere

    /// Every session called `key` (as `SymbolBook.key`) is now `name`: in
    /// History, the session running or waiting to be saved, today's plan and
    /// the name field; the symbol follows. If `name` is another subject's,
    /// the two become one. Undo puts it all back. False when nothing could
    /// be renamed (a blank name, or History can't be changed).
    @discardableResult
    func renameSubject(key: String, to name: String) -> Bool {
        let cleaned = ActiveSession.cleanName(name)
        let newKey = SymbolBook.key(for: cleaned)
        guard let history, !key.isEmpty, !newKey.isEmpty else { return false }
        let merges = mergesInto(cleaned, from: key)
        let records: [UUID: String]
        do {
            records = try history.renameAll(history.spellings(of: key), to: cleaned)
        } catch {
            Log.store.error("Couldn't rename a subject: \(error, privacy: .public)")
            return false
        }
        settleHistoryUndo()
        // Both names' picks as they were (one name when only the spelling changes).
        var symbols: [String: String?] = [:]
        for name in [key, newKey] { symbols.updateValue(symbolBook.picks[name], forKey: name) }
        let planBefore = plannedSet
        let fieldBefore = lastSessionName()
        let shown = symbolBook.symbol(for: key)
        symbolBook.rename(from: key, to: cleaned)
        // The symbol it showed goes with it, even one only suggested by the
        // old name; merging into another subject keeps that one's.
        if !merges, symbolBook.picks[newKey] == nil, shown != SymbolCatalog.unnamed {
            symbolBook.pick(shown, for: cleaned)
        }
        let engineChanges = engine.rename(key: key, to: cleaned)
        if var plan = plannedSet {
            plan.rename(key: key, to: cleaned)
            plannedSet = plan
        }
        if SymbolBook.key(for: fieldBefore) == key { setLastSessionName(cleaned) }
        historyUndo = .rename(SubjectRename(name: cleaned, records: records, engine: engineChanges,
                                            symbols: symbols, plan: planBefore, field: fieldBefore))
        historyChanged()
        // A break's alert names what's next, which may have been renamed.
        if let session = engine.active, session.phase == .rest { scheduleEndAlert(for: session) }
        announce(String(localized: "Renamed to \(Copy.displayName(cleaned)). Undo is available for a few seconds."))
        openHistoryUndoWindow()
        return true
    }

    /// Whether `name` is already another subject's, so renaming to it merges the two.
    func mergesInto(_ name: String, from key: String) -> Bool {
        let newKey = SymbolBook.key(for: name)
        guard !newKey.isEmpty, newKey != key, let history else { return false }
        return !((try? history.spellings(of: newKey)) ?? []).isEmpty
    }

    private func undoRename(_ rename: SubjectRename) {
        do {
            try history?.restoreNames(rename.records)
        } catch {
            Log.store.error("Couldn't put names back: \(error, privacy: .public)")
            return
        }
        clearUndoableDeletion()
        engine.restoreNames(rename.engine)
        var book = symbolBook
        for (key, pick) in rename.symbols { book.picks[key] = pick }
        symbolBook = book
        if rename.plan == nil || rename.plan?.isFor(day: today, calendar: calendar) == true { plannedSet = rename.plan }
        if lastSessionName() == rename.name { setLastSessionName(rename.field) }
        historyChanged()
    }

    func renameSession(_ id: UUID, to name: String) {
        do {
            guard let old = try history?.rename(id: id, to: name) else { return }
            symbolBook.rename(from: old, to: name)
        } catch {
            Log.store.error("Couldn't rename a session: \(error, privacy: .public)")
            return
        }
        historyChanged()
    }

    // MARK: Symbols

    /// The symbol a session with this name shows.
    func symbol(for name: String) -> String { symbolBook.symbol(for: name) }

    /// Picks the symbol for every session with this name, past and future.
    func setSymbol(_ symbol: String, for name: String) {
        let before = symbolBook
        symbolBook.pick(symbol, for: name)
        if symbolBook != before { historyChanged() }
        ClockinTips.note(ClockinTips.symbolPicked)
    }

    /// Forgets symbols for names no session has any more: not saved, not
    /// waiting to be saved, not running and not typed.
    func pruneSymbols() {
        guard let history, !symbolBook.picks.isEmpty else { return }
        do {
            var names = try history.distinctNames()
            names.formUnion(engine.pendingRecords.map(\.name))
            switch engine.stage {
            case .idle: break
            case .active(let session): names.insert(session.name)
            case .focusComplete(let focus): names.insert(focus.name)
            }
            if let moment = engine.breakOver { names.insert(moment.name) }
            names.insert(lastSessionName())
            // Planned and not yet run: a symbol picked for it is kept.
            names.formUnion(plannedSet?.slots.map(\.name) ?? [])
            symbolBook.prune(keeping: names)
        } catch {
            Log.store.error("Couldn't read names to tidy symbols: \(error, privacy: .public)")
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
        if writesHealth { mindful.removeAll() }
        engine.discardAllPending()
        clearUndoableDeletion()
        symbolBook = SymbolBook()
        thoughts = ThoughtBook()
        plannedSet = nil
        historyChanged()
    }

    /// What restoring `data` would change. Nothing is saved yet.
    func planImport(of data: Data) throws -> HistoryExport.ImportPlan {
        guard let history else { throw HistoryExport.ImportError.unreadable }
        let backup = try HistoryExport.readBackup(data)
        let existing = try history.sessions(ids: Set(backup.sessions.map(\.id)))
        return HistoryExport.plan(backup, existing: existing, symbols: symbolBook, now: engine.now())
    }

    /// Saves a restore worked out by `planImport`, all at once.
    func importSessions(_ plan: HistoryExport.ImportPlan) throws {
        guard let history else { return }
        try history.upsert(plan.changes)
        symbolBook.merge(plan.symbols)
        thoughts.merge(plan.thoughts)
        clearUndoableDeletion()
        historyChanged()
    }

    /// Redraws today's totals wherever they show outside the app.
    func historyChanged() {
        if let session = engine.active { syncLiveActivity(session) }
        refreshWidgets()
    }

    /// Undo is gone without the change being settled: it was undone, or
    /// History was erased or restored.
    private func clearUndoableDeletion() {
        historyUndoExpiry?.cancel()
        historyUndoExpiry = nil
        historyUndo = nil
    }

    // MARK: Lifecycle

    /// Restores the engine at launch, then clears anything it no longer explains.
    func restore() {
        dropStalePlan()
        engine.restore()
        endOrphanedActivities()
        // An alarm left from a session that's gone. One ringing for a finished
        // session keeps going until it's stopped or the screen moves on.
        if engine.stage == .idle { alarm.cancel() }
        pruneSymbols()
        pruneThoughts()
        ClockinTips.focusRunning = engine.active?.phase == .focus
        ClockinTips.hasFinished = !((try? history?.distinctNames()) ?? []).isEmpty
        refreshWidgets()
    }

    /// Catches up after returning to the foreground, including a day that
    /// turned over while the app was suspended.
    func reconcile() {
        engine.reconcile()
        focusSound.retryIfWaiting()
        endOrphanedActivities()
        // Health writes that waited for the phone to be unlocked.
        if writesHealth { Task { await mindful.flush() } }
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
        await withoutSounds {
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
    }

    /// When idle nothing should be on the Lock Screen or in the Dynamic Island,
    /// e.g. a card left by a session that ended while the app wasn't running.
    /// `endAll` lists activities off the main actor, so this is cheap when there are none.
    /// Ends a card left with nothing to show. "Break's over" keeps its card
    /// while it lasts, for the Lock Screen's Start focus.
    private func endOrphanedActivities() {
        if engine.stage == .idle, engine.breakOver == nil { liveActivity.endAll() }
    }

    /// Waits for side effects still in flight: the end alert and Live Activity
    /// updates. Intents that run while the app is in the background await this
    /// so the system doesn't suspend the app before they land.
    func settle() async {
        await notifications.flush()
        await alarm.flush()
        await liveActivity.flush()
        await mindful.flush()
    }

    /// Re-reads whether alerts and Live Activities are allowed. Called at launch
    /// and on every return to the foreground, which covers coming back from the
    /// permission prompt or from Settings.
    func refreshAlertStatus() async {
        healthPermission = mindful.permission
        let notificationStatus = await notifications.authorizationStatus()
        let activitiesEnabled = await liveActivity.areActivitiesEnabled()
        if settings.ringAtEnd && alarm.permission == .denied {
            alertStatus = .alarmsOff
            return
        }
        alertStatus = switch notificationStatus {
        case .notDetermined: .notAsked
        case .denied: .notificationsOff
        default: activitiesEnabled ? .ready : .liveActivitiesOff
        }
    }

    /// An ending found after the fact has already been alerted, or, after the
    /// clock jumped forward, would be alerted late. Either way the notification
    /// is stale. A live ending's alert is playing right now, so it stays. The
    /// alarm rings until someone stops it, so only one from long ago goes.
    private func clearLateAlert(_ freshness: Freshness) {
        if freshness != .live { notifications.cancel() }
        if freshness == .stale { alarm.cancel() }
    }

    // MARK: End alert

    /// The alarm stands in for the notification when it's switched on and allowed.
    private var ringsAlarm: Bool { settings.ringAtEnd && alarm.permission == .authorized }

    /// One alert for the end of the phase: the alarm or the notification, never both.
    private func scheduleEndAlert(for session: ActiveSession) {
        if ringsAlarm {
            notifications.cancel()
            alarm.schedule(for: session)
        } else {
            alarm.cancel()
            notifications.schedule(for: session, completedToday: completedToday,
                                   nextName: session.phase == .rest ? nextPlanned?.name : nil)
        }
    }

    private func cancelEndAlert() {
        notifications.cancel()
        alarm.cancel()
    }

    /// "Ring when time's up" in Settings. Turning it on asks for permission the
    /// first time; a session already running gets the new kind of alert at once.
    func setRingAtEnd(_ on: Bool) async {
        settings.ringAtEnd = on
        if on, alarm.permission == .notDetermined {
            _ = await alarm.requestPermission()
        }
        if let session = engine.active, !session.isPaused { scheduleEndAlert(for: session) }
        await refreshAlertStatus()
    }

    // MARK: App icon

    /// Settings › App icon: Tick at work, or Tick on a break.
    func chooseAppIcon(_ choice: AppIconChoice) async {
        await appIcon.choose(choice)
        appIconChoice = appIcon.current
    }

    // MARK: Health

    /// Health access, re-read with the alert status. Observed by Settings.
    private(set) var healthPermission: HealthPermission = .notDetermined

    /// The toggle is on and Health allows it.
    private var writesHealth: Bool { settings.saveToHealth && mindful.permission == .authorized }

    /// The session just finished, or just given its overtime, goes to Health.
    private func saveFinishedToHealth() {
        guard writesHealth, let focus = engine.stage.completedFocus else { return }
        mindful.save(focus)
    }

    /// "Save to Apple Health" in Settings. Turning it on asks the first time;
    /// refused, the toggle goes back off and Settings says why. Sessions
    /// finished from now on are written; earlier ones aren't.
    func setSaveToHealth(_ on: Bool) async {
        settings.saveToHealth = on
        if on, mindful.permission == .notDetermined {
            _ = await mindful.requestPermission()
        }
        healthPermission = mindful.permission
        if on, healthPermission != .authorized { settings.saveToHealth = false }
    }

    /// "Start break" on the end-of-focus alarm: starts that session's break,
    /// if it's still the one waiting for it.
    func alarmStartBreak(after sessionID: UUID?) async {
        await withoutSounds {
            engine.reconcile()
            if let focus = engine.stage.completedFocus, sessionID == nil || sessionID == focus.id {
                engine.startBreak()
            }
            await settle()
        }
    }

    // MARK: Siri, Shortcuts and the control

    /// The name typed on the Focus screen last, for sessions started elsewhere.
    @ObservationIgnored var lastSessionName: () -> String = {
        UserDefaults.standard.string(forKey: "lastSessionName") ?? ""
    }
    /// Puts a name in the Focus screen's field.
    @ObservationIgnored var setLastSessionName: (String) -> Void = {
        UserDefaults.standard.set($0, forKey: "lastSessionName")
    }

    /// Sets Focus up to run a past session again: its name in the field and
    /// its planned length on the dial (the setting, as turning the dial
    /// would). Doesn't start it, and does nothing while a session runs.
    @discardableResult
    func prepareFocus(name: String, planned: TimeInterval?) -> Bool {
        guard engine.active == nil else { return false }
        setLastSessionName(name)
        if let length = SessionLength(planned: planned), length != settings.length { settings.length = length }
        return true
    }

    /// Each intent may wake the app in the background: catch up with the
    /// clock first, act, then wait for the alerts and Live Activity to land.
    func intentStart(minutes: Int?, name: String?) async -> IntentOutcome {
        await withoutSounds {
            engine.reconcile()
            let outcome: IntentOutcome
            if let session = engine.active {
                outcome = .alreadyRunning(phase: session.phase, remaining: session.remaining(at: engine.now()))
            } else {
                let length = minutes.map(SessionLength.init(minutes:))
                engine.start(name: name ?? lastSessionName(), length: length)
                outcome = .started(focus: engine.active?.plannedDuration ?? plan.focus)
            }
            await settle()
            return outcome
        }
    }

    /// "+5 min" from the Lock Screen card, for the session it shows.
    func lockScreenExtend(sessionID: UUID?) async {
        await withoutSounds {
            engine.reconcile()
            guard let session = engine.active, sessionID == nil || session.id == sessionID else { return }
            engine.extend()
            // Too late or too much: redraw the card, so the button goes.
            if engine.active?.extendedSeconds == session.extendedSeconds, let active = engine.active {
                syncLiveActivity(active)
            }
            await settle()
        }
    }

    func intentPark(_ text: String) async -> IntentOutcome {
        await withoutSounds {
            engine.reconcile()
            guard engine.active?.phase == .focus else { return .nowhereToPark }
            return park(text) ? .parked : .nowhereToPark
        }
    }

    func intentPause() async -> IntentOutcome {
        await withoutSounds {
            engine.reconcile()
            engine.pause()
            let outcome: IntentOutcome = engine.active.map { .paused(remaining: $0.remaining(at: engine.now())) }
                ?? .nothingRunning
            await settle()
            return outcome
        }
    }

    func intentResume() async -> IntentOutcome {
        await withoutSounds {
            engine.reconcile()
            engine.resume()
            let outcome: IntentOutcome = engine.active.map { .resumed(remaining: $0.remaining(at: engine.now())) }
                ?? .nothingRunning
            await settle()
            return outcome
        }
    }

    /// Never throws work away: focus past its first minute ends and keeps
    /// its minutes; a break ends; a finished session is put away.
    func intentStop() async -> IntentOutcome {
        await withoutSounds {
            engine.reconcile()
            let outcome: IntentOutcome
            switch engine.stage {
            case .active(let session) where session.phase == .focus:
                if engine.canFinishEarly(at: engine.now()) {
                    engine.finishEarly()
                    outcome = .finished(kept: engine.stage.completedFocus?.focusSeconds ?? 0)
                } else {
                    engine.cancel()
                    outcome = .cancelled
                }
            case .active:
                engine.skipBreak()
                outcome = .breakEnded
            case .focusComplete:
                engine.skipBreak()
                outcome = .dismissed
            case .idle:
                outcome = .nothingRunning
            }
            await settle()
            return outcome
        }
    }

    /// What the app's big button would do right now.
    func intentPrimary() async -> IntentOutcome {
        await withoutSounds {
            engine.reconcile()
            switch engine.stage {
            case .idle:
                return await intentStart(minutes: nil, name: nil)
            case .active(let session):
                return session.isPaused ? await intentResume() : await intentPause()
            case .focusComplete(let focus):
                let length = engine.breakLength(after: focus)
                engine.startBreak()
                await settle()
                return .breakStarted(length)
            }
        }
    }

    /// Moves `today` to the current day. True if it changed.
    @discardableResult
    private func refreshToday() -> Bool {
        let start = calendar.startOfDay(for: engine.now())
        guard start != today else { return false }
        today = start
        dropStalePlan()
        return true
    }

    /// Re-sends the session to the Lock Screen and the end alert, and the day's totals to the widget.
    private func resyncSurfaces() {
        if let session = engine.active {
            syncLiveActivity(session)
            scheduleEndAlert(for: session)
        }
        refreshWidgets()
    }

    private func syncLiveActivity(_ session: ActiveSession) {
        let now = engine.now()
        liveActivity.sync(with: session, completedToday: completedToday,
                          breakDuration: session.nextBreakSeconds ?? plan.shortBreak,
                          symbol: symbol(for: session.name),
                          canExtend: session.phase == .focus && engine.canExtend(at: now),
                          next: session.phase == .rest ? nextUp : nil)
        scheduleExtendOffer(for: session, now: now)
    }

    /// "+5 min" shows on the Lock Screen in the last five minutes. A card
    /// changes only when the app updates it, so the app does, if it's still
    /// running then: always while a focus sound plays, otherwise only if it
    /// happens to be.
    private func scheduleExtendOffer(for session: ActiveSession, now: Date) {
        extendOffer?.cancel()
        guard schedulesTimers, session.phase == .focus, let end = session.endDate else { return }
        let opens = end.addingTimeInterval(-SessionEngine.extensionStep)
        guard opens > now else { return }
        extendOffer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(opens.timeIntervalSince(now) + 0.5))
            guard !Task.isCancelled, let self, let active = self.engine.active, active.id == session.id else { return }
            self.syncLiveActivity(active)
        }
    }

    private func refreshWidgets() {
        widgets.reload(with: widgetSnapshot())
    }

    /// Today's sessions with their names and symbols, and this week's totals.
    func widgetSnapshot() -> WidgetSnapshot {
        let now = engine.now()
        let saved = TodayStats.fetchRecords(on: now, calendar: calendar, context: container.mainContext)
        let savedIDs = Set(saved.map(\.id))
        let waiting = engine.pendingRecords(on: now).filter { !savedIDs.contains($0.id) }
        let sessions = saved.map {
            WidgetSnapshot.Session(id: $0.id, completedAt: $0.completedAt, seconds: $0.focusSeconds,
                                   countsAsFull: $0.row.countsAsFull, name: $0.name, symbol: symbol(for: $0.name),
                                   startedAt: $0.startedAt)
        } + waiting.map {
            WidgetSnapshot.Session(id: $0.id, completedAt: $0.completedAt, seconds: $0.focusSeconds,
                                   countsAsFull: $0.countsAsFull, name: $0.name, symbol: symbol(for: $0.name),
                                   startedAt: $0.startedAt)
        }
        let week = calendar.weekInterval(containing: now)
        let weekRecords = (try? container.mainContext.fetch(FetchDescriptor<FocusRecord>(
            predicate: FocusRecord.completed(in: week)))) ?? []
        let totals = TodayStats.weekTotals(saved: weekRecords.map(\.row), pending: engine.pendingRecords,
                                           containing: now, calendar: calendar)
        var snapshot = WidgetSnapshot(sessions: sessions, week: totals, writtenAt: now)
        snapshot.next = nextUp
        return snapshot
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
                                     alarm: NoAlarm(), widgets: SilentEffects(), haptics: SilentEffects(), announce: { _ in })

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
    func sync(with session: ActiveSession, completedToday: Int, breakDuration: TimeInterval, symbol: String,
              canExtend: Bool, next: NextUp?) {}
    func showFocusDone(completedToday: Int, breakDuration: TimeInterval, lingers: Bool) {}
    func showBreakDone() {}
    func endAll() {}
    func areActivitiesEnabled() async -> Bool { true }
    func flush() async {}
    func schedule(for session: ActiveSession, completedToday: Int, nextName: String?) {}
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
        case .paused, .resumed, .extended, .overtimeKept: .selection
        case .finishedEarly: .impact(weight: .medium, intensity: 0.6)
        case .cancelled: .warning
        case .breakStarted: .impact(flexibility: .soft, intensity: 0.7)
        case .breakSkipped: .impact(weight: .light)
        case .breakFinished(let freshness): freshness == .stale ? nil : .success
        case .focusCompleted, .completionDismissed, .restored, .historySaved, .breakOverEnded, .breakStyleChanged, nil: nil
        }
    }
}
