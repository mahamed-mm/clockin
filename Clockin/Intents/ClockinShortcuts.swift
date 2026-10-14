import AppIntents

/// Phrases Siri knows without setup, and the actions Spotlight and the
/// Shortcuts app offer.
struct ClockinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(), phrases: [
            "Start a focus in \(.applicationName)",
            "Focus with \(.applicationName)",
            "Start \(.applicationName)",
        ], shortTitle: "Start Focus", systemImageName: "play.fill")
        AppShortcut(intent: PauseFocusIntent(), phrases: [
            "Pause \(.applicationName)",
            "Pause my focus in \(.applicationName)",
        ], shortTitle: "Pause", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeFocusIntent(), phrases: [
            "Resume \(.applicationName)",
            "Resume my focus in \(.applicationName)",
        ], shortTitle: "Resume", systemImageName: "play.fill")
        AppShortcut(intent: StopFocusIntent(), phrases: [
            "Stop \(.applicationName)",
            "Stop my focus in \(.applicationName)",
        ], shortTitle: "Stop", systemImageName: "stop.fill")
    }
}
