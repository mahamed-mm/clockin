import SwiftUI

/// What Tick is doing. Tick never decays or scolds: even an interrupted
/// session is met kindly.
enum TickPose: String, CaseIterable, Sendable {
    /// Waiting for a session: upright, eager, a hand hovering by the crown.
    case ready
    /// A focus session running: headphones on, leaning into it.
    case working
    /// Paused: arms crossed, a foot tapping.
    case waiting
    /// A focus session finished: mid-jump, arms up.
    case done
    /// A break: leaning back on one hand, a mug in the other.
    case onBreak
    /// The end alarm ringing: squashed and shaking.
    case ringing
    /// Saying hello where there's nothing yet.
    case hello
    /// A session stopped early: a little disappointed, never cross.
    case interrupted
    /// Proud: a set of four done (Clockin keeps no streaks).
    case streak
    /// Night, or nothing to do: asleep.
    case sleeping
}

/// Tick's colours, all from the asset catalog's Tick colour sets, each
/// with a light and a dark value. The face and its features are the same
/// in both; the limbs, which stand against the page, follow the ink.
struct TickPalette: Sendable {
    var face: Color
    /// The filled part of the ring: the time left.
    var ring: Color
    /// The ring's empty part, a muted terracotta.
    var track: Color
    /// The bright round end of the time left.
    var cap: Color
    /// The crown, and the mug and headphones.
    var crown: Color
    /// Eyes, mouth, the eyebrow hand and the outlines.
    var eyes: Color
    var cheeks: Color
    /// Arms and legs: drawn on the page.
    var limbs: Color
    /// The whole ring when a session is done.
    var doneGold: Color
    /// The whole ring while the alarm rings.
    var ringingRed: Color
    /// Sparkles, the star, alarm and vibration lines, the tongue.
    var effects: Color
    var shadow: Color

    /// Tick from the asset catalog in `bundle` (the app's own by default;
    /// the icon script passes the catalog it compiles).
    static func assets(in bundle: Bundle? = nil) -> TickPalette {
        func named(_ name: String) -> Color { Color("Tick\(name)", bundle: bundle) }
        return TickPalette(face: named("Face"), ring: named("Ring"), track: named("Track"), cap: named("Cap"),
                           crown: named("Crown"), eyes: named("Eyes"), cheeks: named("Cheeks"), limbs: named("Limbs"),
                           doneGold: named("DoneGold"), ringingRed: named("RingingRed"), effects: named("Effects"),
                           shadow: named("Shadow"))
    }

    /// The app icon's Tick: deep terracotta limbs, so one picture reads on
    /// the light and the dark icon, and on the Settings thumbnails.
    static func icon(in bundle: Bundle? = nil) -> TickPalette {
        var palette = assets(in: bundle)
        palette.limbs = Color("TickLimbsIcon", bundle: bundle)
        palette.shadow = .clear
        return palette
    }

    static var standard: TickPalette { assets() }
}

/// The parts of Tick that move, so one drawing serves the stills and the
/// animations. All zero is the still pose.
struct TickMotion: Equatable, Sendable {
    /// 0 eyes as the pose has them, 1 shut.
    var blink: Double = 0
    /// Up and down, in Tick units (the figure is 100 across).
    var bob: Double = 0
    /// Extra lean, in degrees.
    var lean: Double = 0
    /// 0...1 through one rise of the mug's steam.
    var steam: Double = 0
    /// 0...1 of the "ding" hop.
    var hop: Double = 0
    /// -1...1, a sideways shake (the alarm).
    var tremble: Double = 0
    /// The ring's time left, 0...1, instead of the pose's own.
    var ring: Double? = nil

    static let still = TickMotion()
}

/// How much detail fits: hand-made touches only when large, the full pose
/// simplified in between, and just the head when tiny.
enum TickDetail: Sendable {
    /// 120 pt and up: an outline a little heavier on one side, the crown
    /// a touch off centre, a faint grain on the face.
    case handmade
    /// The full pose, cleaner, with bolder limbs and props.
    case simplified
    /// Under 40 pt: ring, crown and eyes, plus a mouth from 14 pt. The
    /// smallest is solid shapes only.
    case glyph(mouth: Bool)

    static func fitting(points: Double) -> TickDetail {
        if points >= 120 { return .handmade }
        if points >= 40 { return .simplified }
        return .glyph(mouth: points >= 14)
    }
}

/// Tick, Clockin's mascot: a little cream-and-terracotta kitchen timer
/// whose ring is its own timer and whose crown is the start button. Drawn
/// from shapes on a 100-unit square, choosing its detail from its size.
struct TickFigure: View {
    var pose: TickPose
    var palette: TickPalette
    var motion: TickMotion = .still
    /// Nil picks the detail from the size it's drawn at.
    var detail: TickDetail? = nil

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let scale = side / 100
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: scale, y: scale)
            TickDrawing(pose: pose, palette: palette, motion: motion,
                        detail: detail ?? .fitting(points: side)).draw(in: &context)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
