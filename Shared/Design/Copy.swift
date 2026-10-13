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
    /// "+5 min"
    static func extend(seconds: TimeInterval) -> String {
        String(localized: "+\(Int(seconds / 60)) min")
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
