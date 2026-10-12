import Foundation

/// Focus and break lengths to choose from. The cadence stays fixed: a break
/// after every focus, started by hand.
enum Preset: String, CaseIterable, Identifiable, Sendable {
    case classic
    case deep
    case short

    var id: Self { self }

    var focus: TimeInterval {
        switch self {
        case .classic: 25 * 60
        case .deep: 50 * 60
        case .short: 15 * 60
        }
    }

    var shortBreak: TimeInterval {
        switch self {
        case .classic: 5 * 60
        case .deep: 10 * 60
        case .short: 3 * 60
        }
    }

    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .deep: String(localized: "Deep")
        case .short: String(localized: "Short")
        }
    }

    /// "25 min focus · 5 min break"
    var detail: String {
        String(localized: "\(TimeFormat.duration(focus)) focus · \(TimeFormat.duration(shortBreak)) break")
    }
}

/// What the user picked in Settings. Saved as JSON in the App Group.
/// Decoding never fails: a missing or unknown value falls back to its
/// default, so settings written by another build still load.
struct TimerSettings: Codable, Equatable, Sendable {
    var preset: Preset = .classic

    init(preset: Preset = .classic) {
        self.preset = preset
    }

    private enum CodingKeys: String, CodingKey { case preset }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try? container.decodeIfPresent(String.self, forKey: .preset)
        preset = raw.flatMap(Preset.init(rawValue:)) ?? .classic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset.rawValue, forKey: .preset)
    }

    var plan: TimerPlan {
        TimerPlan(focus: preset.focus, shortBreak: preset.shortBreak)
    }
}

/// The lengths a new session gets. Taken when a session starts, so changing
/// Settings mid-session changes nothing already running.
struct TimerPlan: Equatable, Sendable {
    var focus: TimeInterval
    var shortBreak: TimeInterval

    static let classic = TimerSettings().plan
    /// Debug test timers: seconds instead of minutes.
    static let test = TimerPlan(focus: 10, shortBreak: 5)
}

protocol SettingsStoring {
    func load() -> TimerSettings
    func save(_ settings: TimerSettings)
}

struct DefaultsSettingsStore: SettingsStoring {
    var defaults: UserDefaults = SharedStore.defaults
    var key = "settings.v1"

    func load() -> TimerSettings {
        guard let data = defaults.data(forKey: key) else { return TimerSettings() }
        do {
            return try JSONDecoder().decode(TimerSettings.self, from: data)
        } catch {
            Log.store.error("Unreadable settings; using defaults: \(error, privacy: .public)")
            return TimerSettings()
        }
    }

    func save(_ settings: TimerSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: key)
        } catch {
            Log.store.error("Couldn't save settings: \(error, privacy: .public)")
        }
    }
}

final class InMemorySettingsStore: SettingsStoring {
    var settings: TimerSettings

    init(_ settings: TimerSettings = TimerSettings()) {
        self.settings = settings
    }

    func load() -> TimerSettings { settings }
    func save(_ settings: TimerSettings) { self.settings = settings }
}
