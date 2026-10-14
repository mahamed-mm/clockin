#if DEBUG
import Foundation
import SwiftData

/// Fills an empty store with a believable week of focus sessions, for
/// screenshots. Runs only with the `-DemoData` launch argument, and only when
/// no sessions are saved yet, so it can never mix with real history.
enum DemoData {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-DemoData") }

    private static let names = ["Chemistry", "Reading: Dune", "Spanish vocab",
                                "Thesis outline", "Linear algebra", "Journaling"]

    @MainActor
    static func seedIfRequested(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        guard isRequested, (try? context.fetchCount(FetchDescriptor<FocusRecord>())) == 0 else { return }

        let today = calendar.startOfDay(for: now)
        var week = calendar
        week.firstWeekday = 2
        let monday = week.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let pastCounts = [3, 4, 2, 5, 3, 4]

        var day = monday
        var index = 0
        while day < today {
            let count = pastCounts[index % pastCounts.count]
            for slot in 0..<count {
                let end = day.addingTimeInterval(TimeInterval(9 * 3600 + slot * 35 * 60) + Preset.classic.focus)
                insert(name: names[(index + slot) % names.count], endingAt: end, into: context)
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today
            index += 1
        }

        // Three sessions earlier today, ending well before now.
        for slot in 0..<3 {
            let end = now.addingTimeInterval(-TimeInterval((3 - slot) * 35 * 60) + 300)
            insert(name: names[slot], endingAt: max(end, today.addingTimeInterval(Preset.classic.focus)), into: context)
        }
        try? context.save()
    }

    /// Saves a session to open on, before `AppServices` loads the saved state:
    /// - `-DemoFinishing`: a focus session that runs out 3 seconds after launch.
    /// - `-DemoOvertime`: one that ran out four minutes ago, kept going since.
    /// - `-DemoBreak`: a break halfway through, spent as `-DemoBreakStyle`
    ///   says (rest, stretch or breathe). Seconds long with `-ShortTimers`.
    @MainActor
    static func prepareFinishingSession(now: Date = .now) {
        let arguments = ProcessInfo.processInfo.arguments
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
                                    breakStyle: style, breakStyleFrom: 0)
        DefaultsSessionStateStore().save(PersistedSessionState(active: session))
    }

    private static func insert(name: String, endingAt end: Date, into context: ModelContext) {
        context.insert(FocusRecord(id: UUID(), name: name, startedAt: end.addingTimeInterval(-Preset.classic.focus),
                                   completedAt: end, focusSeconds: Preset.classic.focus))
    }
}
#endif
