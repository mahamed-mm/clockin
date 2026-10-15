#if DEBUG
import Foundation
import SwiftData

/// Fills an empty store with six believable weeks of focus sessions
/// (`DemoHistory`), for screenshots. Runs only with the `-DemoData` launch
/// argument, and only when no sessions are saved yet, so it can never mix
/// with real history.
enum DemoData {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-DemoData") }

    @MainActor
    static func seedIfRequested(into services: AppServices, now: Date = DemoClock.now) {
        let context = services.container.mainContext
        guard isRequested, (try? context.fetchCount(FetchDescriptor<FocusRecord>())) == 0 else { return }
        for session in DemoHistory.make(now: now, calendar: services.calendar) {
            context.insert(FocusRecord(id: UUID(), name: session.name, startedAt: session.startedAt,
                                       completedAt: session.completedAt, focusSeconds: session.focusSeconds,
                                       plannedSeconds: session.plannedSeconds,
                                       timeZoneIdentifier: services.calendar.timeZone.identifier,
                                       outcome: session.outcome))
        }
        try? context.save()
        for (name, symbol) in DemoHistory.picks { services.setSymbol(symbol, for: name) }
    }

    /// Saves a session to open on, before `AppServices` loads the saved state:
    /// - `-DemoFinishing`: a focus session that runs out 3 seconds after launch.
    /// - `-DemoOvertime`: one that ran out four minutes ago, kept going since.
    /// - `-DemoBreakOver`: a break that ran out 30 seconds ago.
    /// - `-DemoBreak`: a break halfway through, spent as `-DemoBreakStyle`
    ///   says (rest, stretch or breathe) from launch. Seconds long with `-ShortTimers`.
    @MainActor
    static func prepareFinishingSession(now: Date = .now) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-DemoBreakOver") {
            let moment = BreakOverMoment(endedAt: now.addingTimeInterval(-30), name: "Thesis outline", wasLong: false)
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
        let session = ActiveSession(id: UUID(), name: "Thesis outline", phase: .focus,
                                    plannedDuration: Preset.classic.focus,
                                    focusStartedAt: now.addingTimeInterval(end - Preset.classic.focus),
                                    state: .running(endDate: now.addingTimeInterval(end)))
        DefaultsSessionStateStore().save(PersistedSessionState(active: session))
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
