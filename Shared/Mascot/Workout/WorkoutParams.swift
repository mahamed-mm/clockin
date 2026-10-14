import Foundation

/// Everything the workout's look reads, from Tick's energy: how fast and
/// far it punches, how long it rests, how it breathes, sweats and stands,
/// and which face it wears. The one place the fatigue is tuned.
struct WorkoutParams: Equatable, Sendable {
    /// The face Tick wears between hits (a hit squeezes the eyes on its own).
    enum Face: Sendable {
        /// The eyebrow hand angled down, the mouth set.
        case determined
        /// One eye squinting, the mouth gritted.
        case strained
        /// Half-lidded, mouth open, tongue out.
        case panting
    }

    /// Multiplies every move's speed: 1 is full speed.
    var tempo: Double
    /// How far punches and kicks reach, 0...1 of full.
    var reach: Double
    /// Seconds in guard between combos.
    var rest: ClosedRange<Double>
    /// How high Tick bounces on its toes in guard, 0...1.
    var bounce: Double
    /// Seconds per breath when breathing hard; nil breathes only in calm
    /// spells now and then.
    var breathPeriod: Double?
    /// How much a breath grows Tick: 0.02 is 2%.
    var breathDepth: Double
    /// Sweat drops a second.
    var sweatRate: Double
    /// Forward hunch, in degrees.
    var hunch: Double
    /// How far the gloves drop from the face in guard, in Tick units.
    var guardDrop: Double
    var face: Face
    /// How flushed the cheeks are, 0...1.
    var flush: Double

    init(_ energy: WorkoutEnergy) {
        let p = energy.phaseProgress
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
        switch energy.phase {
        case .warmUp:
            self.init(tempo: 0.8, reach: 0.6, rest: 1.5...2.5, bounce: 1, breathPeriod: nil, breathDepth: 0.02,
                      sweatRate: 0, hunch: 0, guardDrop: 0, face: .determined, flush: 0)
        case .strong:
            // Eases slowly, so a long session doesn't look the same at both ends.
            self.init(tempo: mix(1, 0.85), reach: 1, rest: 1...2, bounce: mix(0.8, 0.5), breathPeriod: nil,
                      breathDepth: 0.02, sweatRate: 0, hunch: mix(0, 2), guardDrop: 0, face: .determined, flush: 0)
        case .tired:
            self.init(tempo: mix(0.85, 0.45), reach: mix(1, 0.6), rest: mix(3, 4.5)...mix(4.5, 6),
                      bounce: mix(0.5, 0), breathPeriod: mix(2.2, 1.5), breathDepth: mix(0.025, 0.04),
                      sweatRate: mix(0.2, 0.8), hunch: mix(2, 8), guardDrop: mix(0, 6),
                      face: p < 0.5 ? .determined : .strained, flush: mix(0.3, 0.8))
        case .exhausted:
            // Hands on knees; a weak jab every 6–10 s.
            self.init(tempo: 0.4, reach: 0.5, rest: 6...10, bounce: 0, breathPeriod: 1.2, breathDepth: 0.05,
                      sweatRate: 1, hunch: 14, guardDrop: 6, face: .panting, flush: 1)
        case .finalPush:
            // One last flurry, upright and determined.
            self.init(tempo: 1.3, reach: 1, rest: 0...0, bounce: 0, breathPeriod: 1.2, breathDepth: 0.05,
                      sweatRate: 1, hunch: 0, guardDrop: 0, face: .strained, flush: 1)
        }
    }

    init(tempo: Double, reach: Double, rest: ClosedRange<Double>, bounce: Double, breathPeriod: Double?,
         breathDepth: Double, sweatRate: Double, hunch: Double, guardDrop: Double, face: Face, flush: Double) {
        self.tempo = tempo
        self.reach = reach
        self.rest = rest
        self.bounce = bounce
        self.breathPeriod = breathPeriod
        self.breathDepth = breathDepth
        self.sweatRate = sweatRate
        self.hunch = hunch
        self.guardDrop = guardDrop
        self.face = face
        self.flush = flush
    }
}
