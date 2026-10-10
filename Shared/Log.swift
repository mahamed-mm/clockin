import OSLog

/// Unified logging, readable in Console.app with subsystem `com.moha.clockin`.
/// Log session names with `privacy: .private`; they're the user's own words.
enum Log {
    private static let subsystem = "com.moha.clockin"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let liveActivity = Logger(subsystem: subsystem, category: "live-activity")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
