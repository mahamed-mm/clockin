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

    /// Under "Break's over" in the app: "Next: Thesis outline · session 3 of 4".
    static func nextSession(name: String, position: Int, setSize: Int) -> String {
        String(localized: "Next: \(displayName(name)) · session \(position) of \(setSize)")
    }

    /// Under the name on a "Break's over" card: "Next: session 3 of 4".
    static func nextPosition(_ position: Int, of setSize: Int) -> String {
        String(localized: "Next: session \(position) of \(setSize)")
    }

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
    static var startFocus: String { String(localized: "Start focus") }
    /// "Start Chemistry", a quick action on the Home Screen icon.
    static func startNamed(_ name: String) -> String { String(localized: "Start \(name)") }
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

    /// First launch, under the dial.
    static var dragToSet: String { String(localized: "Drag the knob to set the time") }
    /// After the very first session.
    static var wholeApp: String { String(localized: "That's the whole app.") }
    static var wholeAppDetail: String { String(localized: "Pause, +5 and History are there when you need them.") }

    /// "+5 min" read aloud: "Add 5 minutes".
    static func extendSpoken(seconds: TimeInterval) -> String {
        String(localized: "Add \(TimeFormat.spokenDuration(seconds))")
    }

    // MARK: Breaks

    /// The break screen's style chips, as a group.
    static var duringThisBreak: String { String(localized: "During this break") }

    /// The dial's label while breathing.
    static var breatheIn: String { String(localized: "Breathe in") }
    static var breatheOut: String { String(localized: "Breathe out") }

    /// The dial for VoiceOver while breathing: "Breathe, in for 4 seconds, out for 6".
    static func breatheSpoken(inhale: Int, exhale: Int) -> String {
        String(localized: "Breathe, in for \(inhale) seconds, out for \(exhale)")
    }

    /// The dial's label for each stretch.
    static func stretchName(_ move: StretchMove) -> String {
        switch move {
        case .neckRoll: String(localized: "Neck roll")
        case .shoulderShrug: String(localized: "Shoulder shrug")
        case .reachUp, .backToWork: String(localized: "Reach up")
        case .sideStretch: String(localized: "Side stretch")
        case .wristCircles: String(localized: "Wrist circles")
        case .eyeRest: String(localized: "Look far away")
        }
    }

    /// The dial's label once the stretches are over and the break goes on as a rest.
    static var stretchesDone: String { String(localized: "Stretches done") }

    /// Why Stretch can't be chosen with this little of the break left.
    static var noTimeToStretch: String { String(localized: "Too little of the break left to stretch") }

    /// The dial for VoiceOver while stretching: "Stretch, 2 of 4, shoulder shrug".
    static func stretchSpoken(index: Int, count: Int, move: StretchMove) -> String {
        let name = move == .eyeRest ? String(localized: "look at something far away") : stretchName(move).localizedLowercase
        return String(localized: "Stretch, \(index) of \(count), \(name)")
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
        return String(localized: "Paused at \(TimeFormat.time(TimeFormat.shown(pausedAt)))")
    }

    /// "1 hour, 15 minutes of focus today": a widget's big total, read aloud.
    static func spokenFocusedToday(seconds: TimeInterval) -> String {
        String(localized: "\(TimeFormat.spokenDuration(TimeFormat.shownSeconds(seconds))) of focus today")
    }

    /// "1 h 9 min today", for the Lock Screen.
    static func focusedToday(seconds: TimeInterval) -> String {
        String(localized: "\(TimeFormat.duration(seconds)) today")
    }

    /// "Monday 12 October, today: 2 sessions, 50 minutes", or "…, upcoming"
    /// for a day still to come. The date is there because the strip can
    /// show any week.
    static func daySpoken(_ entry: DayTotal, today: Date, calendar: Calendar,
                          locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide)
        let day = entry.day.formatted(style)
        if calendar.isDate(entry.day, inSameDayAs: today) {
            return String(localized: "\(day), today: \(Copy.sessions(entry.sessions)), \(TimeFormat.spokenDuration(entry.seconds))")
        }
        if entry.day > today {
            return String(localized: "\(day), upcoming")
        }
        return String(localized: "\(day): \(Copy.sessions(entry.sessions)), \(TimeFormat.spokenDuration(entry.seconds))")
    }

    /// "+2 more", under the large widget's list.
    static func moreSessions(_ count: Int) -> String { String(localized: "+\(count) more") }

    // MARK: Symbols

    /// What VoiceOver calls each symbol in the picker.
    static func symbolName(_ id: String) -> String {
        switch id {
        case "book.closed.fill": String(localized: "Book")
        case "books.vertical.fill": String(localized: "Books")
        case "graduationcap.fill": String(localized: "Graduation cap")
        case "pencil": String(localized: "Pencil")
        case "briefcase.fill": String(localized: "Briefcase")
        case "chevron.left.forwardslash.chevron.right": String(localized: "Code")
        case "function": String(localized: "Function")
        case "flask.fill": String(localized: "Flask")
        case "globe": String(localized: "Globe")
        case "music.note": String(localized: "Music note")
        case "paintbrush.pointed.fill": String(localized: "Paintbrush")
        case "pencil.and.ruler.fill": String(localized: "Pencil and ruler")
        case "dumbbell.fill": String(localized: "Dumbbell")
        case "figure.mind.and.body": String(localized: "Meditation")
        case "house.fill": String(localized: "House")
        case "fork.knife": String(localized: "Fork and knife")
        case "envelope.fill": String(localized: "Envelope")
        case "person.2.fill": String(localized: "Two people")
        case "calendar": String(localized: "Calendar")
        case "lightbulb.fill": String(localized: "Light bulb")
        case "magnifyingglass": String(localized: "Magnifying glass")
        case "chart.bar.fill": String(localized: "Bar chart")
        case "hammer.fill": String(localized: "Hammer")
        case "leaf.fill": String(localized: "Leaf")
        default: id
        }
    }

    static var changeSymbol: String { String(localized: "Change symbol") }

    /// "Symbol for Chemistry"
    static func symbolFor(_ name: String) -> String { String(localized: "Symbol for \(displayName(name))") }

    // MARK: History

    /// "Chemistry, 19:00 to 19:25": a block on the day's ribbon, for VoiceOver.
    static func ribbonBlock(name: String, from start: Date, to end: Date) -> String {
        String(localized: "\(name), \(TimeFormat.time(start)) to \(TimeFormat.time(end))")
    }

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
    static func ends(_ date: Date) -> String { String(localized: "Ends \(TimeFormat.time(TimeFormat.shown(date)))") }

    /// "Break until 14:30"
    static func breakUntil(_ date: Date) -> String {
        String(localized: "Break until \(TimeFormat.time(TimeFormat.shown(date)))")
    }

    // MARK: History's subject filter (`subject` nil is "Other")

    /// "Shows only Chemistry sessions": a "By subject" row's hint.
    static func showsOnly(_ subject: String?) -> String {
        subject.map { String(localized: "Shows only \($0) sessions") }
            ?? String(localized: "Shows only the other sessions")
    }

    /// The hint once a row is picked, and on the chip that clears it.
    static var showsEverySession: String { String(localized: "Shows every session") }

    /// "Showing only Chemistry": the chip above the list, read aloud.
    static func showingOnly(_ subject: String?) -> String {
        subject.map { String(localized: "Showing only \($0)") }
            ?? String(localized: "Showing only the other sessions")
    }

    static var clearFilter: String { String(localized: "Clear filter") }

    /// "No Chemistry sessions this week."
    static func noSessionsThisWeek(_ subject: String?) -> String {
        subject.map { String(localized: "No \($0) sessions this week.") }
            ?? String(localized: "No other sessions this week.")
    }

    /// "No Chemistry sessions": a dimmed day in the week strip, read aloud.
    static func noSessions(_ subject: String?) -> String {
        subject.map { String(localized: "No \($0) sessions") } ?? String(localized: "No other sessions")
    }

    // MARK: Focus sound

    static var focusSound: String { String(localized: "Focus sound") }

    /// "Focus sound: Rain", the session chip's speaker for VoiceOver.
    static func focusSoundSpoken(_ sound: FocusSound) -> String {
        String(localized: "Focus sound: \(sound.title)")
    }

    static var volume: String { String(localized: "Volume") }

    /// Headphones came out, or it was paused from the Lock Screen.
    static var focusSoundStopped: String {
        String(localized: "Stopped for this session. Pick a sound to play it again.")
    }

    // MARK: Parked thoughts

    static var parkThought: String { String(localized: "Park a thought") }
    static var parkPlaceholder: String { String(localized: "A thought for later") }
    static var thoughtParked: String { String(localized: "Parked for after this session.") }

    /// "2 parked", on the session chip. Never a score: just how many are waiting.
    static func parked(_ count: Int) -> String { String(localized: "\(count) parked") }

    static var parkedThoughts: String { String(localized: "Parked thoughts") }
    /// A cancelled session's thoughts, kept on the Focus screen.
    static var parkedEarlier: String { String(localized: "Parked earlier") }
    static var copyAll: String { String(localized: "Copy all") }
    static var copied: String { String(localized: "Copied") }
    static var share: String { String(localized: "Share") }
    static var clear: String { String(localized: "Clear") }
    static var thoughtDone: String { String(localized: "Done") }
    static var markDone: String { String(localized: "Ticks it off") }
    static var markNotDone: String { String(localized: "Puts it back on the list") }

    /// "2 thoughts parked", the chip read aloud.
    static func parkedSpoken(_ count: Int) -> String { String(localized: "\(count) thoughts parked") }

    // MARK: Tips

    static var tipCrownTitle: String { String(localized: "Tick's crown is a button") }
    static var tipCrownMessage: String { String(localized: "Tap it to start, and again to pause.") }
    static var tipSymbolTitle: String { String(localized: "Pick a symbol") }
    static var tipSymbolMessage: String {
        String(localized: "Tap the icon by the name to choose one. It shows wherever that name does.")
    }
    static var tipHistoryTapTitle: String { String(localized: "Tap a day or a subject") }
    static var tipHistoryTapMessage: String {
        String(localized: "A day shows its sessions on the ribbon. A subject shows only its sessions.")
    }
    static var tipHistoryMenuTitle: String { String(localized: "Hold a session") }
    static var tipHistoryMenuMessage: String {
        String(localized: "Touch and hold to rename it, change its symbol, start it again or delete it.")
    }
    static var tipBreakChipsTitle: String { String(localized: "Spend the break your way") }
    static var tipBreakChipsMessage: String { String(localized: "Rest, stretch with Tick, or breathe along.") }
    static var tipParkTitle: String { String(localized: "Park a stray thought") }
    static var tipParkMessage: String {
        String(localized: "During focus, tap the notepad on the session. It waits here for when you're done.")
    }

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
