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
    var detail: String { SessionLength.preset(self).detail }

    /// The length chip on the Focus screen: "25 min".
    var chipTitle: String { SessionLength.preset(self).chipTitle }

    /// The chip for VoiceOver: "Classic, 25 minutes focus, 5 minutes break".
    var spokenSummary: String { SessionLength.preset(self).spokenSummary }
}

/// How long the next focus session is: one of the presets, or minutes set
/// by dragging the dial.
enum SessionLength: Hashable, Sendable {
    case preset(Preset)
    case custom(minutes: Int)

    /// What the dial can be set to, in five-minute steps.
    static let minuteRange = 5...60
    static let minuteStep = 5

    /// Snaps `minutes` to the dial. A preset's length comes back as that
    /// preset, so its chip stays lit.
    /// The length a past session was planned at, to start it again; nil
    /// for a session saved without one.
    init?(planned: TimeInterval?) {
        guard let planned, planned > 0 else { return nil }
        self.init(minutes: Int((planned / 60).rounded()))
    }

    init(minutes: Int) {
        let step = Self.minuteStep
        let snapped = ((minutes + step / 2) / step) * step
        let clamped = min(max(snapped, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
        if let preset = Preset.allCases.first(where: { Int($0.focus) == clamped * 60 }) {
            self = .preset(preset)
        } else {
            self = .custom(minutes: clamped)
        }
    }

    var focus: TimeInterval {
        switch self {
        case .preset(let preset): preset.focus
        case .custom(let minutes): TimeInterval(minutes * 60)
        }
    }

    var shortBreak: TimeInterval {
        switch self {
        case .preset(let preset): preset.shortBreak
        case .custom(let minutes): Self.shortBreak(forFocusMinutes: minutes)
        }
    }

    var minutes: Int { Int(focus / 60) }

    /// A fifth of the focus, between 3 and 15 minutes. The presets follow
    /// the same rule: 15 → 3, 25 → 5, 50 → 10.
    static func shortBreak(forFocusMinutes minutes: Int) -> TimeInterval {
        let fifth = (Double(minutes) / 5).rounded()
        return min(max(fifth, 3), 15) * 60
    }

    var title: String {
        switch self {
        case .preset(let preset): preset.title
        case .custom: String(localized: "Custom")
        }
    }

    /// "35 min focus · 7 min break"
    var detail: String {
        String(localized: "\(TimeFormat.duration(focus)) focus · \(TimeFormat.duration(shortBreak)) break")
    }

    /// The length chip on the Focus screen: "25 min".
    var chipTitle: String { TimeFormat.duration(focus) }

    /// The chip for VoiceOver: "Custom, 35 minutes focus, 7 minutes break".
    var spokenSummary: String {
        String(localized: """
            \(title), \(TimeFormat.spokenDuration(focus)) focus, \(TimeFormat.spokenDuration(shortBreak)) break
            """)
    }
}

/// What Tick does through a focus session.
enum MascotFocusStyle: String, CaseIterable, Identifiable, Sendable {
    /// Boxing and kicking in bursts, tiring as the time runs out.
    case workout
    /// In guard, breathing, tired near the end; no punches.
    case calm
    /// The plain working pose, headphones on.
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .workout: String(localized: "Workout")
        case .calm: String(localized: "Calm")
        case .off: String(localized: "Off")
        }
    }
}

/// Light or dark, or whatever the phone is set to.
enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

/// What the user picked in Settings. Saved as JSON in the App Group.
/// Decoding never fails: a missing or unknown value falls back to its
/// default, so settings written by another build still load.
struct TimerSettings: Codable, Equatable, Sendable {
    var preset: Preset = .classic
    /// Minutes set on the dial; nil uses `preset`. Always a dial value that
    /// isn't a preset's length.
    var customMinutes: Int?
    /// A longer break after every fourth full session of the day.
    var longBreak = true
    var appearance: Appearance = .system
    /// Turning the phone on its side during a session shows the bedside clock.
    var bedsideWhenSideways = true
    /// History's week line written by the on-device model, where there is one.
    var weekSummaries = true
    /// An alarm at the end of each phase, through Silent and Focus, instead of
    /// a notification. Off until chosen, since it asks for permission.
    var ringAtEnd = false
    /// Finished focus sessions go to Health as Mindful Minutes. Off until chosen.
    var saveToHealth = false
    /// Tick through a focus session: working out, calm, or the plain pose.
    var mascotDuringFocus: MascotFocusStyle = .workout
    /// What each break starts as; the break screen can change it for that break.
    var duringBreaks: BreakStyle = .rest
    /// The kitchen timer's clicks: the dial's ratchet, Start, Pause and Resume.
    var timerSounds = true
    /// What plays through a focus session, unless the session picks another.
    var focusSound: FocusSound = .off
    /// The focus sound's own level, 0 to 1, under the phone's volume.
    var focusSoundVolume = 0.6
    /// The focus sound plays over other apps' audio rather than stopping it.
    var mixFocusSound = false

    init(preset: Preset = .classic, longBreak: Bool = true, appearance: Appearance = .system,
         bedsideWhenSideways: Bool = true) {
        self.preset = preset
        self.longBreak = longBreak
        self.appearance = appearance
        self.bedsideWhenSideways = bedsideWhenSideways
    }

    /// The next session's length. Choosing a preset clears a custom length;
    /// a custom length keeps the preset underneath for when it's chosen again.
    var length: SessionLength {
        get { customMinutes.map { .custom(minutes: $0) } ?? .preset(preset) }
        set {
            switch SessionLength(minutes: newValue.minutes) {
            case .preset(let preset):
                self.preset = preset
                customMinutes = nil
            case .custom(let minutes):
                customMinutes = minutes
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case preset, customMinutes, longBreak, appearance, bedsideWhenSideways, weekSummaries, ringAtEnd, saveToHealth
        case mascotDuringFocus, duringBreaks, timerSounds, focusSound, focusSoundVolume, mixFocusSound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try? container.decodeIfPresent(String.self, forKey: .preset)
        self.preset = preset.flatMap(Preset.init(rawValue:)) ?? .classic
        // Only a length the dial could have set; anything else uses the preset.
        if let minutes = try? container.decodeIfPresent(Int.self, forKey: .customMinutes),
           case .custom(let snapped) = SessionLength(minutes: minutes), snapped == minutes {
            customMinutes = minutes
        }
        longBreak = (try? container.decodeIfPresent(Bool.self, forKey: .longBreak)) ?? true
        let appearance = try? container.decodeIfPresent(String.self, forKey: .appearance)
        self.appearance = appearance.flatMap(Appearance.init(rawValue:)) ?? .system
        bedsideWhenSideways = (try? container.decodeIfPresent(Bool.self, forKey: .bedsideWhenSideways)) ?? true
        weekSummaries = (try? container.decodeIfPresent(Bool.self, forKey: .weekSummaries)) ?? true
        ringAtEnd = (try? container.decodeIfPresent(Bool.self, forKey: .ringAtEnd)) ?? false
        saveToHealth = (try? container.decodeIfPresent(Bool.self, forKey: .saveToHealth)) ?? false
        let mascot = try? container.decodeIfPresent(String.self, forKey: .mascotDuringFocus)
        mascotDuringFocus = mascot.flatMap(MascotFocusStyle.init(rawValue:)) ?? .workout
        let breaks = try? container.decodeIfPresent(String.self, forKey: .duringBreaks)
        duringBreaks = breaks.flatMap(BreakStyle.init(rawValue:)) ?? .rest
        timerSounds = (try? container.decodeIfPresent(Bool.self, forKey: .timerSounds)) ?? true
        let sound = try? container.decodeIfPresent(String.self, forKey: .focusSound)
        focusSound = sound.flatMap(FocusSound.init(rawValue:)) ?? .off
        let volume = try? container.decodeIfPresent(Double.self, forKey: .focusSoundVolume)
        focusSoundVolume = volume.map { min(1, max(0, $0)) } ?? 0.6
        mixFocusSound = (try? container.decodeIfPresent(Bool.self, forKey: .mixFocusSound)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset.rawValue, forKey: .preset)
        try container.encodeIfPresent(customMinutes, forKey: .customMinutes)
        try container.encode(longBreak, forKey: .longBreak)
        try container.encode(appearance.rawValue, forKey: .appearance)
        try container.encode(bedsideWhenSideways, forKey: .bedsideWhenSideways)
        try container.encode(weekSummaries, forKey: .weekSummaries)
        try container.encode(ringAtEnd, forKey: .ringAtEnd)
        try container.encode(saveToHealth, forKey: .saveToHealth)
        try container.encode(mascotDuringFocus.rawValue, forKey: .mascotDuringFocus)
        try container.encode(duringBreaks.rawValue, forKey: .duringBreaks)
        try container.encode(timerSounds, forKey: .timerSounds)
        try container.encode(focusSound.rawValue, forKey: .focusSound)
        try container.encode(focusSoundVolume, forKey: .focusSoundVolume)
        try container.encode(mixFocusSound, forKey: .mixFocusSound)
    }

    var plan: TimerPlan {
        TimerPlan(focus: length.focus, shortBreak: length.shortBreak,
                  longBreak: longBreak ? TimerPlan.longBreakLength : nil)
    }
}

/// The lengths a new session gets. Taken when a session starts, so changing
/// Settings mid-session changes nothing already running.
struct TimerPlan: Equatable, Sendable {
    var focus: TimeInterval
    var shortBreak: TimeInterval
    /// Nil when long breaks are off.
    var longBreak: TimeInterval?

    /// Full sessions in a set; the last one earns the long break.
    static let sessionsPerSet = 4
    static let longBreakLength: TimeInterval = 15 * 60

    static let classic = TimerSettings().plan

    /// Debug test timers: seconds instead of minutes.
    func asTestTimers() -> TimerPlan {
        TimerPlan(focus: 10, shortBreak: 5, longBreak: longBreak == nil ? nil : 15)
    }

    var breaks: BreakLengths { BreakLengths(short: shortBreak, long: longBreak) }
}

/// The breaks a focus session can earn, fixed when it starts.
struct BreakLengths: Codable, Equatable, Sendable {
    var short: TimeInterval
    /// Nil when long breaks were off.
    var long: TimeInterval?

    /// The break after the `position`th full session of the day (1-based).
    func after(position: Int) -> (seconds: TimeInterval, isLong: Bool) {
        if let long, position > 0, position % TimerPlan.sessionsPerSet == 0 { return (long, true) }
        return (short, false)
    }
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
