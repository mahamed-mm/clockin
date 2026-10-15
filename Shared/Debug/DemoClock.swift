#if DEBUG
import Foundation

/// A time of day for screenshots: `-DemoNow 09:41` makes the app and the
/// widgets show today at 09:41. It's an offset from the real clock, so time
/// still moves on. Timers keep the real clock, so countdowns, the Live
/// Activity and the alarm run as usual; only wall-clock reads move (Tick's
/// hour, the `-DemoData` sessions).
enum DemoClock {
    static let argumentKey = "DemoNow"
    /// In the App Group, so the widgets move with the app.
    static let defaultsKey = "demo.clockOffset.v1"

    /// Seconds from `now` to today at "HH:mm", or nil for anything else.
    static func parse(_ value: String?, now: Date, calendar: Calendar) -> TimeInterval? {
        let parts = value?.split(separator: ":", omittingEmptySubsequences: false) ?? []
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), hour < 24, minute < 60,
              let shown = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
        else { return nil }
        return shown.timeIntervalSince(now)
    }

    /// At launch: keeps the offset for the widgets, or clears it so a run
    /// without the argument puts everything back.
    static func prepare(arguments: UserDefaults = .standard, store: UserDefaults = SharedStore.defaults,
                        now: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        if let offset = parse(arguments.string(forKey: argumentKey), now: now, calendar: calendar) {
            store.set(offset, forKey: defaultsKey)
        } else {
            store.removeObject(forKey: defaultsKey)
        }
    }

    /// Zero unless the app was launched with `-DemoNow`.
    static var offset: TimeInterval { SharedStore.defaults.double(forKey: defaultsKey) }

    /// The time shown for now.
    static var now: Date { Date.now.addingTimeInterval(offset) }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isWholeNumber }
}
#endif
