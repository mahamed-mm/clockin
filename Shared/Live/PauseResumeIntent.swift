import AppIntents
import Foundation

/// Lets the app plug its engine into intents that run in the app process.
@MainActor
enum IntentBridge {
    static var togglePause: (() -> Void)?
}

/// Pause/resume button on the Lock Screen and in the Dynamic Island.
struct PauseResumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Focus"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.togglePause?()
        return .result()
    }
}
