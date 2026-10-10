import AppIntents
import Foundation

/// Lets the app plug its engine into intents that run in the app process.
@MainActor
enum IntentBridge {
    /// Toggles the session and returns once its alert and Live Activity
    /// updates are done, so the system can't suspend the app halfway.
    static var togglePause: (@MainActor () async -> Void)?
}

/// Pause/resume button on the Lock Screen and in the Dynamic Island.
struct PauseResumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Focus"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await IntentBridge.togglePause?()
        return .result()
    }
}
