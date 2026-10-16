#if DEBUG
import Foundation
import SwiftData

/// Fills an empty store with fourteen believable weeks of focus sessions
/// (`DemoHistory`), for screenshots. Runs only with the `-DemoData` launch
/// argument, and only when no sessions are saved yet, so it can never mix
/// with real history. Also plans today's set.
enum DemoData {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-DemoData") }

    @MainActor
    static func seedIfRequested(into services: AppServices, now: Date = DemoClock.now) {
        let context = services.container.mainContext
        guard isRequested, (try? context.fetchCount(FetchDescriptor<FocusRecord>())) == 0 else { return }
        let today = services.calendar.startOfDay(for: now)
        var doneToday: [String: UUID] = [:]
        var newest: [String: (id: UUID, at: Date)] = [:]
        for session in DemoHistory.make(now: now, calendar: services.calendar) {
            let id = UUID()
            if session.completedAt > newest[session.name]?.at ?? .distantPast { newest[session.name] = (id, session.completedAt) }
            context.insert(FocusRecord(id: id, name: session.name, startedAt: session.startedAt,
                                       completedAt: session.completedAt, focusSeconds: session.focusSeconds,
                                       plannedSeconds: session.plannedSeconds,
                                       timeZoneIdentifier: services.calendar.timeZone.identifier,
                                       outcome: session.outcome))
            if session.completedAt >= today { doneToday[session.name] = id }
        }
        try? context.save()
        for (name, symbol) in DemoHistory.picks { services.setSymbol(symbol, for: name) }
        services.editSet(demoPlan(day: today, doneToday: doneToday))
        services.seedThoughts(demoThoughtBook(sessions: newest.mapValues(\.id), now: now))
    }

    /// Thoughts kept with recent sessions, two of them ticked off, and one
    /// from a cancelled session, for History's open thoughts.
    static func demoThoughtBook(sessions: [String: UUID], now: Date) -> ThoughtBook {
        func thought(_ text: String, hoursAgo: Double, done: Bool = false) -> ParkedThought {
            ParkedThought(id: UUID(), text: text, parkedAt: now.addingTimeInterval(-hoursAgo * 3_600),
                          done: done ? true : nil)
        }
        var book = ThoughtBook()
        let kept: [(String, [ParkedThought])] = [
            ("Chemistry", [thought("Ask about the titration lab", hoursAgo: 1.8),
                           thought("Print the periodic table", hoursAgo: 1.7, done: true)]),
            ("Thesis outline", [thought("Email Sam about Friday", hoursAgo: 26),
                                thought("Find the 2019 survey", hoursAgo: 27),
                                thought("Book a library room", hoursAgo: 28, done: true)]),
            ("Spanish vocab", [thought("Renew the flashcard app", hoursAgo: 50)]),
        ]
        for (name, thoughts) in kept {
            if let id = sessions[name] { book.file(thoughts, under: id) }
        }
        book.unfile([thought("Book the dentist", hoursAgo: 75)])
        return book
    }

    /// Today's plan: Chemistry, done this morning, then three still to do
    /// (Thesis outline twice).
    static func demoPlan(day: Date, doneToday: [String: UUID]) -> SetPlan {
        var plan = SetPlan(day: day)
        for name in DemoHistory.plan { plan.add(name) }
        if let chemistry = doneToday["Chemistry"] { plan.finish(name: "Chemistry", session: chemistry) }
        return plan
    }

    /// `-DemoSound rain` (or tickTock, brownNoise, fireplace, off): the focus
    /// sound for sessions started this run, and `-DemoMascot calm` (or
    /// workout, off): Tick during focus. As if picked in Settings.
    @MainActor
    static func applyDemoSettings(to services: AppServices) {
        if let sound = UserDefaults.standard.string(forKey: "DemoSound").flatMap(FocusSound.init(rawValue:)) {
            services.settings.focusSound = sound
        }
        if let style = UserDefaults.standard.string(forKey: "DemoMascot").flatMap(MascotFocusStyle.init(rawValue:)) {
            services.settings.mascotDuringFocus = style
        }
    }

    /// Saves a session to open on, before `AppServices` loads the saved state:
    /// - `-DemoFinishing`: a focus session that runs out 3 seconds after launch.
    /// - `-DemoOvertime`: one that ran out four minutes ago, kept going since.
    /// - `-DemoThoughts` with either: two thoughts parked in it.
    /// - `-DemoBreakOver`: a break that ran out 30 seconds ago; with
    ///   `-DemoLongBreak`, the long one after a set.
    /// - `-DemoBreak`: a break halfway through, spent as `-DemoBreakStyle`
    ///   says (rest, stretch or breathe) from launch. Seconds long with `-ShortTimers`.
    @MainActor
    static func prepareFinishingSession(now: Date = .now) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-DemoBreakOver") {
            let moment = BreakOverMoment(endedAt: now.addingTimeInterval(-30), name: "Thesis outline",
                                         wasLong: arguments.contains("-DemoLongBreak"))
            DefaultsSessionStateStore().save(PersistedSessionState(breakOver: moment))
            return
        }
        if arguments.contains("-DemoBreak") {
            prepareBreak(now: now, short: arguments.contains("-ShortTimers"))
            return
        }
        let end: TimeInterval
        if arguments.contains("-DemoFinishing") {
            end = 3
        } else if arguments.contains("-DemoOvertime") {
            end = -(4 * 60 + 10)
        } else {
            return
        }
        var session = ActiveSession(id: UUID(), name: "Thesis outline", phase: .focus,
                                    plannedDuration: Preset.classic.focus,
                                    focusStartedAt: now.addingTimeInterval(end - Preset.classic.focus),
                                    state: .running(endDate: now.addingTimeInterval(end)))
        if arguments.contains("-DemoThoughts") { session.thoughts = demoThoughts(now: now) }
        DefaultsSessionStateStore().save(PersistedSessionState(active: session))
    }

    /// `-DemoThoughts`: two thoughts parked in the demo session.
    static func demoThoughts(now: Date) -> [ParkedThought] {
        [ParkedThought(id: UUID(), text: "Email Sam about Friday", parkedAt: now.addingTimeInterval(-900)),
         ParkedThought(id: UUID(), text: "Book the dentist", parkedAt: now.addingTimeInterval(-420))]
    }

    @MainActor
    private static func prepareBreak(now: Date, short: Bool) {
        let length = short ? TimerPlan.classic.asTestTimers().shortBreak : Preset.classic.shortBreak
        let style = UserDefaults.standard.string(forKey: "DemoBreakStyle").flatMap(BreakStyle.init(rawValue:)) ?? .rest
        let session = ActiveSession(id: UUID(), name: "Thesis outline", phase: .rest, plannedDuration: length,
                                    focusStartedAt: now.addingTimeInterval(-length / 2),
                                    state: .running(endDate: now.addingTimeInterval(length / 2)),
                                    // The style chosen as the app opens, so a stretch starts from the top.
                                    breakStyle: style, breakStyleFrom: style == .rest ? 0 : length / 2)
        DefaultsSessionStateStore().save(PersistedSessionState(active: session))
    }
}
#endif
