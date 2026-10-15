import AppIntents
import Foundation

/// What an intent did, so Siri and Shortcuts can say it back.
enum IntentOutcome: Equatable, Sendable {
    case started(focus: TimeInterval)
    case alreadyRunning(phase: SessionPhase, remaining: TimeInterval)
    case paused(remaining: TimeInterval)
    case resumed(remaining: TimeInterval)
    /// Stopped, keeping the minutes done.
    case finished(kept: TimeInterval)
    /// Stopped in its first minute, so nothing was kept (and it can be undone in the app).
    case cancelled
    case breakStarted(TimeInterval)
    case breakEnded
    case dismissed
    case nothingRunning
    /// Never says the thought back: Siri may be speaking aloud.
    case parked
    case nowhereToPark

    var dialog: String {
        switch self {
        case .started(let focus):
            String(localized: "Focusing for \(TimeFormat.spokenDuration(focus)).")
        case .alreadyRunning(let phase, let remaining):
            phase == .focus
                ? String(localized: "Already focusing. \(TimeFormat.spokenTimeLeft(remaining)).")
                : String(localized: "On a break. \(TimeFormat.spokenTimeLeft(remaining)).")
        case .paused(let remaining):
            String(localized: "Paused. \(TimeFormat.spokenTimeLeft(remaining)).")
        case .resumed(let remaining):
            String(localized: "Back to it. \(TimeFormat.spokenTimeLeft(remaining)).")
        case .finished(let kept):
            String(localized: "Stopped. \(TimeFormat.spokenDuration(kept)) of focus kept.")
        case .cancelled:
            String(localized: "Stopped. It was under a minute, so nothing was kept.")
        case .breakStarted(let seconds):
            String(localized: "Break started: \(TimeFormat.spokenDuration(seconds)).")
        case .breakEnded:
            String(localized: "Break ended.")
        case .dismissed:
            String(localized: "All done.")
        case .nothingRunning:
            String(localized: "Nothing's running in Clockin.")
        case .parked:
            Copy.thoughtParked
        case .nowhereToPark:
            String(localized: "No focus session is running, so there's nowhere to park it.")
        }
    }
}

extension IntentBridge {
    /// Starts focus, for this many minutes and under this name when given.
    static var startFocus: (@MainActor (_ minutes: Int?, _ name: String?) async -> IntentOutcome)?
    static var pauseFocus: (@MainActor () async -> IntentOutcome)?
    static var resumeFocus: (@MainActor () async -> IntentOutcome)?
    /// Stops whatever's running without throwing work away.
    static var stopFocus: (@MainActor () async -> IntentOutcome)?
    /// Whatever the big button in the app would do now.
    static var primaryAction: (@MainActor () async -> IntentOutcome)?
    /// Parks a thought in the running focus session.
    static var parkThought: (@MainActor (_ text: String) async -> IntentOutcome)?
    /// "+5 min" from the Lock Screen, for the session the card shows.
    static var extendFocus: (@MainActor (_ sessionID: UUID?) async -> Void)?
}

/// "+5 min" on the Lock Screen card in the last five minutes of focus.
struct ExtendFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add Five Minutes"
    static let isDiscoverable = false

    /// The session the card shows; a tap meant for another does nothing.
    @Parameter(title: "Session")
    var sessionID: String?

    init() {}

    init(sessionID: UUID?) {
        self.sessionID = sessionID?.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await IntentBridge.extendFocus?(sessionID.flatMap(UUID.init(uuidString:)))
        return .result()
    }
}

/// Puts a thought aside for after the running focus session, from Siri or
/// Shortcuts. A Live Activity intent so it runs in the app, which keeps the
/// session.
struct ParkThoughtIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Park a Thought"
    static let description = IntentDescription("Puts a thought aside for after the focus session that's running.")

    @Parameter(title: "Thought", requestValueDialog: "What's the thought?")
    var thought: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentBridge.parkThought?(thought) ?? .nowhereToPark
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

// All of these are Live Activity intents so they run in the app, which
// owns the timer, even from Control Center or the Lock Screen.

/// "Start a focus in Clockin", and the Start action in Shortcuts.
/// Also an `AudioPlaybackIntent`: the focus sound may start with the session
/// even when it's started from outside the app.
struct StartFocusIntent: LiveActivityIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Start Focus"
    static let description = IntentDescription("Starts a focus session. Without a length, it uses the one set on the dial.")

    @Parameter(title: "Minutes", inclusiveRange: (5, 60))
    var minutes: Int?

    @Parameter(title: "Name")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a focus of \(\.$minutes) minutes called \(\.$name)")
    }

    init() {}

    /// The Lock Screen's "Start focus" after a break: the same name again.
    init(name: String) {
        self.name = name
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentBridge.startFocus?(minutes, name) ?? .nothingRunning
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

struct PauseFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Focus"
    static let description = IntentDescription("Pauses the running session or break.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentBridge.pauseFocus?() ?? .nothingRunning
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

struct ResumeFocusIntent: LiveActivityIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Resume Focus"
    static let description = IntentDescription("Carries on with a paused session or break.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentBridge.resumeFocus?() ?? .nothingRunning
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

struct StopFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Focus"
    static let description = IntentDescription(
        "Ends the session and keeps the minutes done, or ends the break. Under a minute in, nothing is kept.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await IntentBridge.stopFocus?() ?? .nothingRunning
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

/// The Control Center / Lock Screen / Action button control: does what the
/// big button in the app would.
struct FocusButtonIntent: LiveActivityIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Focus Button"
    static let description = IntentDescription("Starts focus, pauses or resumes it, or starts the break.")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = await IntentBridge.primaryAction?()
        return .result()
    }
}

/// What the control shows, worked out from the saved session state, so the
/// widget extension can draw it without the app running.
struct ControlFace: Equatable, Sendable {
    enum Action: Equatable, Sendable { case start, pause, resume, startBreak }

    static let kind = "com.moha.clockin.FocusControl"

    var action: Action
    var title: String
    var symbol: String

    init(action: Action, title: String, symbol: String) {
        self.action = action
        self.title = title
        self.symbol = symbol
    }

    init(state: PersistedSessionState, now: Date) {
        if let session = state.active {
            if session.isFinished(at: now) {
                // Ran out while the app wasn't looking: what it will offer next.
                self = session.phase == .focus ? .startBreak : .start
            } else if session.isPaused {
                self = .resume
            } else {
                self = .pause
            }
        } else if state.completedFocus != nil {
            self = .startBreak
        } else {
            self = .start
        }
    }

    static let start = ControlFace(action: .start, title: String(localized: "Start focus"), symbol: "play.fill")
    static let startBreak = ControlFace(action: .startBreak, title: Copy.startBreakShort, symbol: "cup.and.saucer.fill")
    static let pause = ControlFace(action: .pause, title: String(localized: "Pause"), symbol: "pause.fill")
    static let resume = ControlFace(action: .resume, title: String(localized: "Resume"), symbol: "play.fill")
}
