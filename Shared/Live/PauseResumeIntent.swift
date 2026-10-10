import AppIntents
import Foundation

/// Lets the app plug its engine into intents that run in the app process.
@MainActor
enum IntentBridge {
    /// Pauses (true) or resumes (false) the session with this id, or toggles
    /// when the button didn't say. Returns once the alert and Live Activity
    /// updates are done, so the system can't suspend the app halfway.
    static var setPaused: (@MainActor (_ paused: Bool?, _ sessionID: UUID?) async -> Void)?
}

/// Pause/resume button on the Lock Screen and in the Dynamic Island.
struct PauseResumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Focus"
    static let isDiscoverable = false

    /// True on a Pause button, false on Resume. Saying which, rather than
    /// toggling, means a double tap or an out-of-date card can't flip it back.
    /// Missing on buttons drawn by older builds.
    @Parameter(title: "Pause")
    var pause: Bool?

    /// The session the card was drawn for.
    @Parameter(title: "Session")
    var sessionID: String?

    init() {}

    init(pause: Bool, sessionID: UUID?) {
        self.pause = pause
        self.sessionID = sessionID?.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await IntentBridge.setPaused?(pause, sessionID.flatMap(UUID.init(uuidString:)))
        return .result()
    }
}
