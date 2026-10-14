import Foundation

/// The copy deck: one phrase per moment, shared by the app, the Lock Screen,
/// StandBy, the widget, alerts and VoiceOver, so a moment never reads two
/// ways. Everything goes through `String(localized:)` and the String Catalog
/// (`Shared/Localizable.xcstrings`), which also holds the plural forms.
enum Copy {
    // MARK: Moments

    /// A focus phase ran to its end.
    static var focusComplete: String { String(localized: "Focus complete") }
    /// A focus phase finished with "Finish now".
    static var endedEarly: String { String(localized: "Ended early") }
    /// A break ran to its end.
    static var breakOver: String { String(localized: "Break's over") }
    /// Under "Break's over".
    static var readyWhenYouAre: String { String(localized: "Ready when you are.") }

    /// Under "Focus complete": "Time for a 5-minute break." Test timers
    /// count in seconds, so they read "Time for a 5-second break."
    static func breakLine(seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        if whole < 60 { return String(localized: "Time for a \(whole)-second break.") }
        return String(localized: "Time for a \(whole / 60)-minute break.")
    }

    /// The button that starts it: "Start 5-min break".
    static func startBreak(seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        if whole < 60 { return String(localized: "Start \(whole)-sec break") }
        return String(localized: "Start \(whole / 60)-min break")
    }

    // MARK: Focus controls

    static var finishNow: String { String(localized: "Finish now") }

    /// The end alarm's buttons.
    static var startBreakShort: String { String(localized: "Start break") }
    static var stopAlarm: String { String(localized: "Stop") }
    static var ringing: String { String(localized: "Ringing") }
    /// "+5 min"
    static func extend(seconds: TimeInterval) -> String {
        String(localized: "+\(Int(seconds / 60)) min")
    }

    /// Time worked past the bell, under the dial: "+3 min".
    static func overtimeShort(minutes: Int) -> String {
        String(localized: "+\(minutes) min")
    }

    /// Adds the minutes past the bell to the session.
    static func keepOvertime(minutes: Int) -> String {
        String(localized: "Keep +\(minutes) min")
    }

    static func keepOvertimeSpoken(minutes: Int) -> String {
        String(localized: "Count \(TimeFormat.spokenDuration(TimeInterval(minutes * 60))) more as focus")
    }

    static func keptOvertime(minutes: Int) -> String {
        String(localized: "Kept \(minutes) more min")
    }

    /// The dial's VoiceOver value after the bell: "3 minutes over".
    static func overtimeSpoken(minutes: Int) -> String {
        String(localized: "\(TimeFormat.spokenDuration(TimeInterval(minutes * 60))) over")
    }

    /// "+5 min" read aloud: "Add 5 minutes".
    static func extendSpoken(seconds: TimeInterval) -> String {
        String(localized: "Add \(TimeFormat.spokenDuration(seconds))")
    }

    // MARK: Phases

    static var focus: String { String(localized: "Focus") }
    static var rest: String { String(localized: "Break") }
    static var longBreak: String { String(localized: "Long break") }
    static var paused: String { String(localized: "Paused") }

    /// "Paused at 9:36". The dial already shows the time left; a session
    /// paused by an older build says how much instead: "Paused · 12:34 left".
    static func pausedMeta(at pausedAt: Date?, remaining: TimeInterval) -> String {
        guard let pausedAt else { return String(localized: "Paused · \(TimeFormat.clock(remaining)) left") }
        return String(localized: "Paused at \(TimeFormat.time(pausedAt))")
    }

    // MARK: History

    /// One calm line about the week under History's strip: "Mostly mornings
    /// this week; Tuesday was your longest day." No names, no praise.
    static func weekSentence(_ facts: WeekFacts, calendar: Calendar) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: calendar.locale ?? .current,
                                     calendar: calendar, timeZone: calendar.timeZone)
        let day = facts.busiestDay.formatted(style.weekday(.wide))
        if facts.sessions == 1 {
            switch facts.firstPart {
            case .morning: return String(localized: "One session this week, on \(day) morning.")
            case .afternoon: return String(localized: "One session this week, on \(day) afternoon.")
            case .evening: return String(localized: "One session this week, on \(day) evening.")
            }
        }
        if facts.daysWithFocus == 1 {
            switch facts.mostlyIn {
            case .morning: return String(localized: "Mostly mornings this week, all on \(day).")
            case .afternoon: return String(localized: "Mostly afternoons this week, all on \(day).")
            case .evening: return String(localized: "Mostly evenings this week, all on \(day).")
            case nil: return String(localized: "All on \(day) this week.")
            }
        }
        switch facts.mostlyIn {
        case .morning: return String(localized: "Mostly mornings this week; \(day) was your longest day.")
        case .afternoon: return String(localized: "Mostly afternoons this week; \(day) was your longest day.")
        case .evening: return String(localized: "Mostly evenings this week; \(day) was your longest day.")
        case nil: return String(localized: "Spread across the day this week; \(day) was your longest day.")
        }
    }

    /// The session's name, or "Focus session" when it has none.
    static func displayName(_ name: String) -> String {
        name.isEmpty ? String(localized: "Focus session") : name
    }

    /// "Break after Organic chemistry", or just "Break" after an unnamed session.
    static func breakAfter(_ name: String) -> String {
        name.isEmpty ? rest : String(localized: "Break after \(name)")
    }

    /// "Ends 14:30"
    static func ends(_ date: Date) -> String { String(localized: "Ends \(TimeFormat.time(date))") }

    /// "Break until 14:30"
    static func breakUntil(_ date: Date) -> String { String(localized: "Break until \(TimeFormat.time(date))") }

    // MARK: Session pills

    /// "2 of 4 today", or "4 of 4 · +2" past the set.
    static func pillsCaption(completed: Int, setSize: Int) -> String {
        let extra = max(0, completed - setSize)
        return extra > 0
            ? String(localized: "\(setSize) of \(setSize) · +\(extra)")
            : String(localized: "\(completed) of \(setSize) today")
    }

    /// "6 focus sessions today", never "6 of 4".
    static func sessionsToday(_ count: Int) -> String {
        String(localized: "\(count) focus sessions today")
    }

    /// The pills read aloud: "2 of 4 today, one in progress". Past a full
    /// set it counts sessions instead ("6 focus sessions today").
    static func pillsSpoken(completed: Int, setSize: Int, inProgress: Bool) -> String {
        let count = completed > setSize
            ? sessionsToday(completed)
            : String(localized: "\(completed) of \(setSize) today")
        return inProgress ? String(localized: "\(count), one in progress") : count
    }

    /// "3 sessions"
    static func sessions(_ count: Int) -> String {
        String(localized: "\(count) sessions")
    }
}
