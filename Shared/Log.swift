import OSLog

/// Unified logging, readable in Console.app with subsystem `com.moha.clockin`.
/// Errors are logged with `privacy: .public` so they survive on device; they
/// come from the system, never from the user. Never log session names.
enum Log {
    private static let subsystem = "com.moha.clockin"

    static let store = Logger(subsystem: subsystem, category: "store")
    static let liveActivity = Logger(subsystem: subsystem, category: "live-activity")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
