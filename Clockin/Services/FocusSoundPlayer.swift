import AVFoundation
import MediaPlayer
import Synchronization

/// What the focus sound is doing, for the session chip's menu and Tick.
enum FocusSoundState: Equatable, Sendable {
    case silent
    case playing(FocusSound)
    /// Asked for from the Lock Screen, Siri or a widget, where iOS wouldn't
    /// let it begin, or stopped by a call that didn't hand the sound back:
    /// it starts when Clockin is next open.
    case waitingForApp(FocusSound)
    /// Headphones came out, or it was paused from Now Playing: off for the
    /// rest of the session unless picked again.
    case stopped(FocusSound)

    var sound: FocusSound? {
        switch self {
        case .silent: nil
        case .playing(let sound), .waitingForApp(let sound), .stopped(let sound): sound
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}

@MainActor
protocol FocusSoundPlaying: AnyObject {
    var state: FocusSoundState { get }
    /// Gets to `cue` (nil: silence) the way `fade` says. `chosen` is a sound
    /// picked by hand, which plays again after headphones came out.
    func follow(_ cue: FocusSoundCue?, fade: FocusSoundFade, chosen: Bool)
    func configure(volume: Double, mixes: Bool)
    /// Starts a sound iOS wouldn't start while Clockin was in the background.
    func retryIfWaiting()
}

/// For tests and previews: never makes a sound.
@MainActor
final class NoFocusSound: FocusSoundPlaying {
    private(set) var state: FocusSoundState = .silent
    func follow(_ cue: FocusSoundCue?, fade: FocusSoundFade, chosen: Bool) {
        state = cue.map { .playing($0.sound) } ?? .silent
    }
    func configure(volume: Double, mixes: Bool) {}
    func retryIfWaiting() {}
}

/// Plays the focus sounds: the loops decoded once into memory, summed by one
/// source node whose level follows a `FocusSoundEnvelope`, so every fade is
/// exact and needs no timer. The audio session is `.playback`, which keeps
/// the sound going on the Lock Screen and keeps Clockin running while it
/// plays, and only then: it stops and lets go of the session as soon as it's
/// silent for good.
@MainActor
@Observable
final class FocusSoundPlayer: FocusSoundPlaying {
    private(set) var state: FocusSoundState = .silent

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var node: AVAudioSourceNode?
    @ObservationIgnored private var renderer: LoopRenderer?
    @ObservationIgnored private var cue: FocusSoundCue?
    @ObservationIgnored private var volume = 0.6
    @ObservationIgnored private var mixes = false
    /// Headphones came out, or Now Playing paused it (the sound only, never
    /// the timer). Cleared by a sound picked by hand or a new session.
    @ObservationIgnored private var stoppedForSession = false
    @ObservationIgnored private var halting: Task<Void, Never>?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                               queue: .main) { [weak self] note in
                let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                MainActor.assumeIsolated { self?.interrupted(began: began, resumes: options.contains(.shouldResume)) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                               queue: .main) { [weak self] note in
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                MainActor.assumeIsolated { if reason == .oldDeviceUnavailable { self?.headphonesCameOut() } }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartAfterConfigurationChange() }
            },
        ]
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remote(play: true) }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remote(play: false) }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remote(play: !(self?.state.isPlaying ?? true)) }
            return .success
        }
    }

    // MARK: Following the session

    func follow(_ cue: FocusSoundCue?, fade: FocusSoundFade, chosen: Bool) {
        Log.audio.info("Follow \(cue?.sound.rawValue ?? "nothing", privacy: .public), \(String(describing: fade), privacy: .public)")
        if chosen || fade == .startIn { stoppedForSession = false }
        self.cue = cue
        guard let cue, !stoppedForSession else {
            fadeToSilence(fade)
            return
        }
        if let renderer, renderer.sound == cue.sound, engine.isRunning {
            halting?.cancel()
            let now = Self.hostNow()
            renderer.envelope.withLock { envelope in
                let bell = Self.host(cue.bell)
                envelope = envelope.to == 1 ? FocusSoundEnvelope(from: envelope.fade(at: now), to: 1, start: now,
                                                                 length: 0, bell: bell)
                    : envelope.fading(to: 1, at: now, fade, bell: bell)
            }
            scheduleHalt()
        } else {
            begin(cue, fade: fade)
        }
    }

    func configure(volume: Double, mixes: Bool) {
        self.volume = volume
        engine.mainMixerNode.outputVolume = Float(volume)
        guard mixes != self.mixes else { return }
        self.mixes = mixes
        if state.isPlaying { _ = activateSession() }
        showNowPlaying()
    }

    func retryIfWaiting() {
        guard case .waitingForApp = state, let cue else { return }
        begin(cue, fade: .resumeIn)
    }

    // MARK: Starting and stopping

    private func begin(_ cue: FocusSoundCue, fade: FocusSoundFade) {
        halting?.cancel()
        loading?.cancel()
        let sound = cue.sound
        let loaded = renderer.flatMap { $0.sound == sound ? $0.bank : nil }
        loading = Task { [weak self] in
            let bank: LoopBank
            if let loaded {
                bank = loaded
            } else {
                do {
                    // Decoding takes a few tens of milliseconds: off the main thread.
                    bank = try await Task.detached(priority: .userInitiated) { try LoopBank(sound) }.value
                } catch {
                    Log.audio.error("Couldn't load a focus sound: \(error, privacy: .public)")
                    return
                }
            }
            guard !Task.isCancelled, let self, self.cue?.sound == sound else { return }
            if loaded == nil { self.attach(bank) }
            guard self.activateSession() else {
                self.state = .waitingForApp(sound)
                return
            }
            let now = Self.hostNow()
            self.renderer?.envelope.withLock {
                $0 = FocusSoundEnvelope().fading(to: 1, at: now, fade, bell: self.cue.map { Self.host($0.bell) })
            }
            do {
                try self.engine.start()
            } catch {
                Log.audio.error("Couldn't start the focus sound: \(error, privacy: .public)")
                self.state = .waitingForApp(sound)
                return
            }
            self.state = .playing(sound)
            Log.audio.info("Playing \(sound.rawValue, privacy: .public)")
            self.showNowPlaying()
            self.scheduleHalt()
        }
    }

    /// Swaps in a sound's loops, replacing any other sound's.
    private func attach(_ bank: LoopBank) {
        if engine.isRunning { engine.stop() }
        if let node { engine.detach(node) }
        let renderer = LoopRenderer(bank: bank)
        let node = Self.makeNode(renderer)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: LoopBank.format)
        engine.mainMixerNode.outputVolume = Float(volume)
        self.renderer = renderer
        self.node = node
    }

    /// Made outside the main actor: the render block runs on the audio thread.
    private nonisolated static func makeNode(_ renderer: LoopRenderer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: LoopBank.format) { _, timestamp, frames, buffers -> OSStatus in
            let stamp = timestamp.pointee
            let host = stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : mach_absolute_time()
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let out = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            renderer.render(frames: Int(frames), at: AVAudioTime.seconds(forHostTime: host), into: out)
            return noErr
        }
    }

    private func fadeToSilence(_ fade: FocusSoundFade) {
        loading?.cancel()
        guard let renderer, engine.isRunning, fade != .now else {
            halt()
            return
        }
        let now = Self.hostNow()
        renderer.envelope.withLock { $0 = $0.fading(to: 0, at: now, fade, bell: $0.bell) }
        scheduleHalt()
    }

    /// Stops the engine and lets go of the audio session once the envelope is
    /// silent for good, so Clockin isn't kept running in silence.
    private func scheduleHalt() {
        halting?.cancel()
        guard let silentFrom = renderer?.envelope.withLock({ $0.silentFrom }) else { return }
        let wait = max(0, silentFrom - Self.hostNow()) + 0.2
        // Before the bell, keep going in silence until the session itself
        // ends: the app hears the bell while it still runs.
        guard renderer?.envelope.withLock({ $0.to == 0 }) == true else { return }
        halting = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.halt()
        }
    }

    private func halt() {
        Log.audio.info("Halting")
        halting?.cancel()
        if engine.isRunning { engine.stop() }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.audio.error("Couldn't let go of the audio session: \(error, privacy: .public)")
        }
        state = stoppedForSession ? cue.map { .stopped($0.sound) } ?? .silent : .silent
        showNowPlaying()
    }

    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: mixes ? [.mixWithOthers] : [])
            // Long buffers: fewer wakeups for a sound that never needs to be quick.
            try session.setPreferredIOBufferDuration(0.1)
            try session.setActive(true)
            return true
        } catch {
            Log.audio.error("Couldn't take the audio session: \(error, privacy: .public)")
            return false
        }
    }

    // MARK: The world outside

    private func interrupted(began: Bool, resumes: Bool) {
        Log.audio.info("Interruption \(began ? "began" : "ended", privacy: .public), resumes: \(resumes)")
        guard let cue else { return }
        if began {
            halting?.cancel()
            state = .waitingForApp(cue.sound)
        } else if resumes, !stoppedForSession {
            begin(cue, fade: .resumeIn)
        }
    }

    private func headphonesCameOut() {
        guard state.isPlaying, let cue else { return }
        stoppedForSession = true
        state = .stopped(cue.sound)
        fadeToSilence(.stopOut)
    }

    private func restartAfterConfigurationChange() {
        Log.audio.info("Configuration changed; running: \(self.engine.isRunning)")
        guard state.isPlaying, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            Log.audio.error("Couldn't restart the focus sound: \(error, privacy: .public)")
        }
    }

    /// Now Playing's play and pause act on the sound only, never the timer.
    private func remote(play: Bool) {
        guard let cue else { return }
        if play {
            follow(cue, fade: .resumeIn, chosen: true)
        } else {
            stoppedForSession = true
            state = .stopped(cue.sound)
            fadeToSilence(.pauseOut)
        }
    }

    /// Without mixing, Clockin is the Now Playing app: the Lock Screen shows
    /// the sound's name, never the session's.
    private func showNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard !mixes, let sound = state.sound, state.isPlaying else {
            center.nowPlayingInfo = nil
            return
        }
        center.nowPlayingInfo = [MPMediaItemPropertyTitle: sound.title,
                                 MPMediaItemPropertyArtist: "Clockin",
                                 MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0]
    }

    // MARK: Clock

    /// The audio clock, in seconds: what the render block sees.
    static func hostNow() -> TimeInterval { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }

    static func host(_ date: Date) -> TimeInterval { hostNow() + date.timeIntervalSinceNow }
}

/// A sound's loops, decoded into memory: about 11 MB for rain, the longest.
private final class LoopBank: @unchecked Sendable {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 32_000, channels: 1)!

    let sound: FocusSound
    let layers: [UnsafeMutableBufferPointer<Float>]

    enum Failure: Error { case missing(String), unreadable(String) }

    init(_ sound: FocusSound) throws {
        self.sound = sound
        var layers: [UnsafeMutableBufferPointer<Float>] = []
        do {
            for name in sound.layers {
                guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else {
                    throw Failure.missing(name)
                }
                let file = try AVAudioFile(forReading: url)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)) else {
                    throw Failure.unreadable(name)
                }
                try file.read(into: buffer)
                guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
                    throw Failure.unreadable(name)
                }
                let copy = UnsafeMutableBufferPointer<Float>.allocate(capacity: Int(buffer.frameLength))
                _ = copy.initialize(from: UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
                layers.append(copy)
            }
        } catch {
            layers.forEach { $0.deallocate() }
            throw error
        }
        self.layers = layers
    }

    deinit { layers.forEach { $0.deallocate() } }
}

/// The audio thread's side: where each loop is up to, and the envelope the
/// main thread sets. Rendering allocates nothing and takes only the
/// envelope's lock, held for a copy.
private final class LoopRenderer: @unchecked Sendable {
    let bank: LoopBank
    let envelope = Mutex(FocusSoundEnvelope())
    private let positions: UnsafeMutablePointer<Int>

    var sound: FocusSound { bank.sound }

    init(bank: LoopBank) {
        self.bank = bank
        positions = .allocate(capacity: max(1, bank.layers.count))
        positions.initialize(repeating: 0, count: max(1, bank.layers.count))
    }

    deinit { positions.deallocate() }

    func render(frames: Int, at time: TimeInterval, into out: UnsafeMutablePointer<Float>) {
        let envelope = self.envelope.withLock { $0 }
        let first = Float(envelope.gain(at: time))
        let last = Float(envelope.gain(at: time + Double(frames) / LoopBank.format.sampleRate))
        let step = frames > 0 ? (last - first) / Float(frames) : 0
        let layers = bank.layers
        for frame in 0..<frames {
            var sample: Float = 0
            for index in layers.indices {
                let layer = layers[index]
                sample += layer[positions[index]]
                positions[index] = positions[index] + 1 == layer.count ? 0 : positions[index] + 1
            }
            out[frame] = sample * (first + step * Float(frame))
        }
    }
}
