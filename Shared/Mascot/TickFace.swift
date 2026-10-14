import SwiftUI

/// Tick's face: eyes, brows and mouth. The shapes change between states
/// behind a blink, so they don't need to morph; the clock-hand eyebrow,
/// the blink and the cheeks animate.
struct TickFace: Equatable, Sendable {
    enum Eyes: Sendable {
        /// Big and bright.
        case eager
        /// Looking down at the work.
        case down
        /// A heavy upper lid: unimpressed.
        case halfLid
        /// Closed in a smile.
        case happy
        /// Content, nearly asleep.
        case sleepy
        case wide
        /// Kind, a little lowered.
        case softDown
        case closed
    }

    /// Plain brows, only where the face needs them.
    enum Brows: Sendable {
        case none
        /// One cocked brow.
        case singleRaised
        /// Both raised at the middle: kind, never cross.
        case innerRaised
    }

    enum Mouth: Sendable {
        case smile
        case content
        case proud
        /// A flat line with a little concentration tongue.
        case focused
        case flat
        /// A small "oh well" smile.
        case kind
        case openSmile
        case bigOpenSmile
        case oh
        case snore
    }

    var eyes: Eyes
    var brows: Brows
    var mouth: Mouth
    /// The clock hand's angle in degrees from straight up, clockwise.
    var browHandAngle: Double
    /// 0 hidden (when plain brows take over) to 1.
    var browHand: Double
    var cheeks: Double = 1
    /// 0 eyes as the state has them, 1 shut.
    var blink: Double = 0
}

extension TickFace {
    /// Tick's face for a state, as drawn on the character sheet.
    init(_ pose: TickPose) {
        switch pose {
        case .ready: self.init(eyes: .eager, brows: .none, mouth: .smile, browHandAngle: 28, browHand: 1)
        case .working: self.init(eyes: .down, brows: .none, mouth: .focused, browHandAngle: -48, browHand: 1)
        case .waiting: self.init(eyes: .halfLid, brows: .singleRaised, mouth: .flat, browHandAngle: 45, browHand: 0)
        case .done: self.init(eyes: .happy, brows: .none, mouth: .bigOpenSmile, browHandAngle: 0, browHand: 1)
        case .onBreak: self.init(eyes: .sleepy, brows: .none, mouth: .content, browHandAngle: 75, browHand: 1)
        case .ringing: self.init(eyes: .wide, brows: .none, mouth: .oh, browHandAngle: 0, browHand: 1)
        case .hello: self.init(eyes: .eager, brows: .none, mouth: .openSmile, browHandAngle: 35, browHand: 1)
        case .interrupted: self.init(eyes: .softDown, brows: .innerRaised, mouth: .kind, browHandAngle: -20, browHand: 1)
        case .streak: self.init(eyes: .happy, brows: .none, mouth: .proud, browHandAngle: 12, browHand: 1)
        case .sleeping: self.init(eyes: .closed, brows: .none, mouth: .snore, browHandAngle: 105, browHand: 1)
        }
    }
}

extension TickFace: Animatable {
    /// The numbers that animate; the shapes switch.
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { AnimatablePair(AnimatablePair(browHandAngle, browHand), AnimatablePair(cheeks, blink)) }
        set {
            browHandAngle = newValue.first.first
            browHand = newValue.first.second
            cheeks = newValue.second.first
            blink = newValue.second.second
        }
    }
}
