import AppIntents
import Foundation

/// "Start break" on the end-of-focus alarm. Runs in the app, which starts
/// the break and sets the next alarm for its end.
struct StartBreakIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Break"
    static let isDiscoverable = false

    /// The focus session the alarm rang for, so an old alarm can't start
    /// the break after a different one.
    @Parameter(title: "Session")
    var sessionID: String?

    init() {}

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await IntentBridge.startBreak?(sessionID.flatMap(UUID.init(uuidString:)))
        return .result()
    }
}
