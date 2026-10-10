import Foundation
import Observation

/// Phase lengths. Release builds always use 25 / 5 minutes.
/// Debug builds can switch to short timers for the current run only, via the
/// Debug menu or the `-ShortTimers` launch argument. Nothing is saved.
enum Durations {
    static let focus: TimeInterval = 25 * 60
    static let shortBreak: TimeInterval = 5 * 60

    @MainActor
    static func duration(for phase: SessionPhase) -> TimeInterval {
        #if DEBUG
        if DevSettings.shared.shortTimers {
            return phase == .focus ? DevSettings.shortFocus : DevSettings.shortBreak
        }
        #endif
        return phase == .focus ? focus : shortBreak
    }

    /// "5-minute", as in "Take a 5-minute break"; "5-second" for short test breaks.
    static func breakPhrase(seconds: TimeInterval) -> String {
        let seconds = Int(seconds)
        return seconds >= 60 ? "\(seconds / 60)-minute" : "\(seconds)-second"
    }

    /// The phrase for the break this process would start. App process only:
    /// the widget extension can't see debug test timers, so it reads the
    /// length from the Live Activity's state instead.
    @MainActor
    static var breakLengthPhrase: String {
        breakPhrase(seconds: duration(for: .rest))
    }
}

#if DEBUG
@MainActor
@Observable
final class DevSettings {
    static let shared = DevSettings()
    static let shortFocus: TimeInterval = 10
    static let shortBreak: TimeInterval = 5

    /// In memory only, so a test setting can never stick across launches.
    var shortTimers = ProcessInfo.processInfo.arguments.contains("-ShortTimers")
    /// Stretches every app animation ×4 so motion can be inspected frame by frame.
    var slowAnimations = ProcessInfo.processInfo.arguments.contains("-SlowAnimations")

    private init() {
        // Clear the flag older builds persisted.
        SharedStore.defaults.removeObject(forKey: "dev.shortTimers")
    }
}
#endif
