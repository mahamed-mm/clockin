import Foundation

/// What the focus sound should be doing: playing `sound` until the bell at
/// `bell`, or nothing (a nil cue). The app works it out from the session
/// after every change; the player gets there with a fade.
struct FocusSoundCue: Equatable, Sendable {
    var sound: FocusSound
    /// When the focus phase runs out. The sound is silent a second before.
    var bell: Date
}

/// How the player gets to a new cue.
enum FocusSoundFade: Equatable, Sendable {
    /// After Start's wind-up: in over 3 s, half a second later.
    case startIn
    /// Resuming, coming back after a call, or picking a sound: in over 3 s.
    case resumeIn
    /// Pausing: out over a second.
    case pauseOut
    /// Cancelling or finishing early: out over half a second.
    case stopOut
    /// The bell or a break: already silent, so it just stops.
    case now

    /// How the sound follows each change to the session; nil leaves it be.
    static func `for`(_ event: SessionEvent) -> FocusSoundFade? {
        switch event {
        case .started: .startIn
        case .resumed, .restored, .extended: .resumeIn
        case .paused: .pauseOut
        case .cancelled, .finishedEarly: .stopOut
        // The bell came after a second of silence; breaks are silent.
        case .focusCompleted, .breakStarted, .breakSkipped, .completionDismissed, .breakFinished: .now
        case .historySaved, .overtimeKept: nil
        }
    }

    /// Seconds before the fade begins.
    var delay: TimeInterval { self == .startIn ? 0.5 : 0 }

    var length: TimeInterval {
        switch self {
        case .startIn, .resumeIn: 3
        case .pauseOut: 1
        case .stopOut: 0.5
        case .now: 0
        }
    }
}

/// The focus sound's level over time: a fade from one level to another,
/// under a ceiling that closes before the bell so the chime or the alarm
/// always plays into silence. Pure, so it can be tested; the player reads
/// it for every buffer it renders, in the audio clock's seconds.
struct FocusSoundEnvelope: Equatable, Sendable {
    var from = 0.0
    var to = 0.0
    var start: TimeInterval = 0
    var length: TimeInterval = 0
    /// When the bell rings; nil while nothing is due.
    var bell: TimeInterval?

    /// Seconds before the bell that the sound starts to fade.
    static let bellFade: TimeInterval = 3
    /// Seconds before the bell that it's silent.
    static let bellQuiet: TimeInterval = 1

    func gain(at time: TimeInterval) -> Double {
        fade(at: time) * ceiling(at: time)
    }

    /// The fade alone, eased so it starts and lands gently.
    func fade(at time: TimeInterval) -> Double {
        guard length > 0 else { return time >= start ? to : from }
        let x = min(1, max(0, (time - start) / length))
        return from + (to - from) * x * x * (3 - 2 * x)
    }

    /// 1 until the bell's fade, then down to 0 a second before the bell.
    func ceiling(at time: TimeInterval) -> Double {
        guard let bell else { return 1 }
        return min(1, max(0, (bell - Self.bellQuiet - time) / (Self.bellFade - Self.bellQuiet)))
    }

    /// From wherever it is at `time`, to `level` the way `fade` says.
    func fading(to level: Double, at time: TimeInterval, _ fade: FocusSoundFade,
                bell: TimeInterval?) -> FocusSoundEnvelope {
        FocusSoundEnvelope(from: self.fade(at: time), to: level, start: time + fade.delay, length: fade.length,
                           bell: bell)
    }

    /// When it's silent for good, if it's heading for silence.
    var silentFrom: TimeInterval? {
        if to == 0 { return start + length }
        return bell.map { $0 - Self.bellQuiet }
    }
}
