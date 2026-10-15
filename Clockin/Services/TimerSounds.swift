import AudioToolbox
import Foundation

/// The kitchen timer's own sounds, made by scripts/make-sounds.sh.
enum TimerSound: String, CaseIterable, Sendable {
    /// One detent of the dial, while dragging the knob.
    case ratchet
    /// Winding up and letting go: a session or break starting.
    case windUp = "wind-up"
    /// Pausing: a soft clunk.
    case clunk
    /// Resuming: a lighter click.
    case click

    var fileName: String { "timer-\(rawValue)" }

    /// The sound for a change the timer went through, if it has one. The end
    /// has its own chime, played by the alert; cancelling and skipping are quiet.
    static func `for`(_ event: SessionEvent) -> TimerSound? {
        switch event {
        case .started, .breakStarted: .windUp
        case .paused: .clunk
        case .resumed: .click
        case .cancelled, .focusCompleted, .breakFinished, .breakSkipped, .completionDismissed, .restored,
             .historySaved, .extended, .finishedEarly, .overtimeKept, .breakOverEnded,
             .breakStyleChanged: nil
        }
    }
}

/// What AppServices needs to play a timer sound, so tests can stand in for it.
@MainActor
protocol TimerSounds: AnyObject {
    func play(_ sound: TimerSound)
}

/// System sounds: the least delay, silenced by the Silent switch, and they
/// mix with whatever's playing rather than stopping or ducking it.
@MainActor
final class SystemTimerSounds: TimerSounds {
    private var loaded: [TimerSound: SystemSoundID] = [:]

    func play(_ sound: TimerSound) {
        guard let id = loaded[sound] ?? load(sound) else { return }
        AudioServicesPlaySystemSound(id)
    }

    private func load(_ sound: TimerSound) -> SystemSoundID? {
        guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: "caf") else {
            Log.store.error("Missing timer sound \(sound.fileName, privacy: .public)")
            return nil
        }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
        loaded[sound] = id
        return id
    }
}

#if DEBUG
extension SystemTimerSounds {
    /// For the debug menu's sounds lab, whatever the setting.
    static let debug = SystemTimerSounds()
}
#endif

/// No sounds, for previews and tests that don't care about them.
@MainActor
final class NoSounds: TimerSounds {
    func play(_ sound: TimerSound) {}
}
