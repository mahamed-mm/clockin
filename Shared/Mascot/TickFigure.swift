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

/// Tick's colours. The face is cream Bakelite and its features dark in
/// both appearances; the limbs, which stand against the page, follow the
/// ink. Kept apart from the asset catalog so the icon script can draw
/// Tick with exact values.
struct TickPalette: Sendable {
    var face: Color
    var rim: Color
    /// Eyes, mouth and the eyebrow hand: drawn on the face.
    var features: Color
    /// Arms and legs: drawn on the page.
    var limbs: Color
    /// The crown, the mug.
    var prop: Color
    /// Cheeks, sparkles, the ring's glowing tip, alarm lines.
    var accent: Color
    var shadow: Color

    static let cream = Color(red: 0.953, green: 0.914, blue: 0.839)
    static let darkInk = Color(red: 0.165, green: 0.129, blue: 0.106)

    /// Exact light or dark values, for the icon script.
    static func fixed(dark: Bool) -> TickPalette {
        TickPalette(face: cream,
                    rim: dark ? Color(red: 0.757, green: 0.345, blue: 0.227) : Color(red: 0.612, green: 0.239, blue: 0.133),
                    features: darkInk,
                    limbs: dark ? Color(red: 0.945, green: 0.902, blue: 0.827) : darkInk,
                    prop: dark ? Color(red: 0.910, green: 0.706, blue: 0.290) : Color(red: 0.890, green: 0.655, blue: 0.184),
                    accent: dark ? Color(red: 0.886, green: 0.451, blue: 0.235) : Color(red: 0.824, green: 0.376, blue: 0.165),
                    shadow: (dark ? Color.black : darkInk).opacity(0.14))
    }
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
