import Foundation

/// Tick's idle life, as a pure function of time: blinks at random 3–6 s
/// apart, two slow breaths now and then, and each state's own loop. Every
/// Tick gets its own `seed`, so two on screen never blink together, and
/// the loops' periods differ so they never line up.
struct TickLoops {
    var pose: TickPose
    /// Shifts the blinks and breathing for this Tick.
    var seed: Double
    /// Whether the state's entry plays first: not when Tick first shows,
    /// or comes back from the background, already in it.
    var entering = false
    /// The calm breathing spells; off while working out, which breathes its own way.
    var breathes = true
    /// A workout starting: working's entry is gloving up, not just the headphones.
    var gearsUp = false

    /// How long the state's entry lasts.
    var entryLength: TimeInterval {
        guard entering else { return 0 }
        return switch pose {
        case .hello: 2.0
        case .working: gearsUp ? WorkoutLoops.gearUpLength : 0.5
        case .ringing: 0.35
        case .done: 0.95
        case .onBreak: 0.45
        case .streak: 0.7
        case .waiting, .interrupted, .sleeping, .ready: 0
        }
    }

    /// The motion `elapsed` seconds after this state began.
    func motion(at elapsed: TimeInterval) -> TickMotion {
        var motion = TickMotion()
        let t = max(0, elapsed)
        motion.blink = blink(at: t)
        motion.breath = breath(at: t, period: breathPeriod)

        switch pose {
        case .ready:
            // Taps the crown about every 8 s.
            motion.crownTap = pulse(t, every: 8, offset: 3, length: 0.5)
        case .working:
            break // Blinks and breathing only: calm, never distracting.
        case .waiting:
            // The toe taps down and up every 1.2 s; the brow lifts now and then.
            motion.footTap = 20 * pulse(t, every: 1.2, offset: 0, length: 0.35)
            motion.browLift = 1.6 * pulse(t, every: 4.5, offset: 1.5, length: 0.7)
        case .ringing:
            // A fast shake, the lines flashing.
            motion.lean = 5 * sin(2 * .pi * t * 9)
            motion.tremble = sin(2 * .pi * t * 13)
            motion.alarmFlash = 0.5 + 0.5 * sin(2 * .pi * t * 3)
            motion.breath = 0
        case .done:
            // A small hop every 2.5 s.
            motion.hop = 0.6 * hop(t, every: 2.5, offset: 1)
        case .onBreak:
            motion.steam = (t / 1.6).truncatingRemainder(dividingBy: 1)
        case .hello:
            break // The wave is its entry; then it settles into ready.
        case .interrupted:
            // One shrug and a sigh, then just breathing.
            motion.shrug = t < 1.4 ? sin(.pi * t / 1.4) : 0
        case .streak:
            motion.twinkle = pulse(t, every: 1.8, offset: 0.4, length: 0.6)
        case .sleeping:
            motion.zeeRise = (t / 3).truncatingRemainder(dividingBy: 1)
        }
        if t < entryLength { addEntry(at: t, to: &motion) }
        return motion
    }

    /// Each state's way in, played once as it begins.
    private func addEntry(at t: TimeInterval, to motion: inout TickMotion) {
        switch pose {
        case .hello:
            // Pops in from 80%, with a little overshoot, then waves three times.
            motion.shrink = t < 0.45 ? 0.2 * (1 - springOut(t / 0.45)) : 0
            if t > 0.35 { motion.wave = sin(2 * .pi * (t - 0.35) / 0.55) * fade(t, end: entryLength) }
        case .working:
            // The headphones slide on from above.
            motion.headphonesAbove = 1 - easeOut(t / entryLength)
        case .ringing:
            motion.squash = sin(.pi * t / entryLength)
        case .done:
            // Crouch, jump, land: squash and stretch. The gold sweeps round
            // and the sparkles burst out at the top of the jump.
            if t < 0.12 {
                motion.squash = 0.7 * sin(.pi / 2 * t / 0.12)
            } else if t < 0.72 {
                let x = (t - 0.12) / 0.6
                motion.hop = 4 * x * (1 - x)
                motion.squash = -0.5 * sin(.pi * x)
            } else {
                motion.squash = 0.5 * sin(.pi * (t - 0.72) / (entryLength - 0.72))
            }
            motion.goldUnswept = 1 - easeOut(min(1, t / 0.6))
            motion.sparklesIn = t < 0.35 ? 1 : 1 - easeOut(min(1, (t - 0.35) / 0.4))
        case .onBreak:
            motion.mugIn = 1 - springOut(t / entryLength)
        case .streak:
            // The star drops onto the crown and bounces.
            motion.starAbove = 1 - springOut(t / entryLength)
        case .waiting, .interrupted, .sleeping, .ready:
            break
        }
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(1, max(0, x)), 3) }

    /// 0 to 1, overshooting by about 15% on the way: a springy arrival.
    private func springOut(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x >= 1 ? 1 : 1 - exp(-6 * x) * cos(10 * x)
    }

    /// 1 until near `end`, then down to 0.
    private func fade(_ t: TimeInterval, end: TimeInterval) -> Double { min(1, max(0, (end - t) / 0.3)) }

    // MARK: When something moves

    /// Whether this state moves all the time (steam, z's, the alarm).
    var isContinuous: Bool { pose == .onBreak || pose == .sleeping || pose == .ringing }

    /// Seconds between frames while moving: 30 a second, but 15 for the
    /// slow drift of steam and z's, which a whole break or a night shows.
    func frameInterval(at t: TimeInterval) -> TimeInterval {
        let slowDrift = (pose == .onBreak || pose == .sleeping) && t >= entryLength
            && blink(at: t) == 0 && breath(at: t, period: breathPeriod) == 0
        return slowDrift ? 1.0 / 15 : 1.0 / 30
    }

    /// The next moment, from `t` on, when anything but breathing moves:
    /// `t` itself if something is moving now. Between moments Tick holds
    /// still, so nothing needs drawing.
    func nextMovement(from t: TimeInterval) -> TimeInterval {
        if isContinuous || t < entryLength { return t }
        var windows = [blinkWindow(from: t)]
        if pose != .ringing, breathes { windows.append(breathWindow(from: t)) }
        switch pose {
        case .ready: windows.append(window(from: t, every: 8, offset: 3, length: 0.5))
        case .waiting:
            windows.append(window(from: t, every: 1.2, offset: 0, length: 0.35))
            windows.append(window(from: t, every: 4.5, offset: 1.5, length: 0.7))
        case .done: windows.append(window(from: t, every: 2.5, offset: 1, length: 0.6))
        case .streak: windows.append(window(from: t, every: 1.8, offset: 0.4, length: 0.6))
        case .interrupted: if t < 1.4 { windows.append(0..<1.4) }
        default: break
        }
        return windows.map { $0.contains(t) ? t : max(t, $0.lowerBound) }.min() ?? t
    }

    /// The next stretch of a repeating moment that hasn't ended by `t`.
    private func window(from t: TimeInterval, every: TimeInterval, offset: TimeInterval, length: TimeInterval) -> Range<TimeInterval> {
        let start = t <= offset ? offset : offset + ((t - offset) / every).rounded(.down) * every
        return start + length > t ? start..<(start + length) : (start + every)..<(start + every + length)
    }

    // MARK: Pieces

    /// The blink that's on at `t`, or the next one.
    private func blinkWindow(from t: TimeInterval) -> Range<TimeInterval> {
        var start = 1.5 + 1.5 * noise(0)
        var index = 1.0
        while start + 0.18 <= t {
            start += 3 + 3 * noise(index)
            index += 1
        }
        return start..<(start + 0.18)
    }

    /// Shut for 0.18 s at random 3–6 s apart (the same "random" for a
    /// given seed, so it can be tested). The first is 1.5–3 s in.
    func blink(at t: TimeInterval) -> Double {
        let window = blinkWindow(from: t)
        guard window.contains(t) else { return 0 }
        let into = t - window.lowerBound
        // Closes quickly, opens a little slower.
        return into < 0.07 ? into / 0.07 : 1 - (into - 0.07) / 0.11
    }

    /// Slower when asleep.
    var breathPeriod: TimeInterval { pose == .sleeping ? 4.6 : 3.2 }

    /// Two slow breaths about every 16 s (always breathing would keep the
    /// screen drawing for a whole session).
    func breathWindow(from t: TimeInterval) -> Range<TimeInterval> {
        window(from: t, every: 16, offset: 2 + 6 * noise(-1), length: 2 * breathPeriod)
    }

    /// 0...1...0 through each breath of a breathing spell, 0 between.
    func breath(at t: TimeInterval, period: TimeInterval) -> Double {
        guard breathes else { return 0 }
        let spell = breathWindow(from: t)
        guard spell.contains(t) else { return 0 }
        return 0.5 - 0.5 * cos(2 * .pi * (t - spell.lowerBound) / period)
    }

    /// A smooth 0...1...0 bump of `length` seconds, every `every` seconds.
    private func pulse(_ t: TimeInterval, every: TimeInterval, offset: TimeInterval, length: TimeInterval) -> Double {
        let into = (t - offset).truncatingRemainder(dividingBy: every)
        guard t >= offset, into < length else { return 0 }
        return sin(.pi * into / length)
    }

    /// Up fast, down with gravity: a hop of 0.6 s.
    private func hop(_ t: TimeInterval, every: TimeInterval, offset: TimeInterval) -> Double {
        let into = (t - offset).truncatingRemainder(dividingBy: every)
        guard t >= offset, into < 0.6 else { return 0 }
        let x = into / 0.6
        return 4 * x * (1 - x)
    }

    /// A number in 0..<1 for this Tick and this index.
    private func noise(_ index: Double) -> Double {
        let x = sin((index + 1) * 12.9898 + seed * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}
