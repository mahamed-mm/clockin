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
struct TickPalette: Equatable, Sendable {
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
    /// Boxing gloves, mustard like the crown, and their darker cuffs.
    var glove: Color
    var gloveCuff: Color

    /// Tick from the asset catalog in `bundle` (the app's own by default;
    /// the icon script passes the catalog it compiles).
    static func assets(in bundle: Bundle? = nil) -> TickPalette {
        func named(_ name: String) -> Color { Color("Tick\(name)", bundle: bundle) }
        return TickPalette(face: named("Face"), ring: named("Ring"), track: named("Track"), cap: named("Cap"),
                           crown: named("Crown"), eyes: named("Eyes"), cheeks: named("Cheeks"), limbs: named("Limbs"),
                           doneGold: named("DoneGold"), ringingRed: named("RingingRed"), effects: named("Effects"),
                           shadow: named("Shadow"), glove: named("Glove"), gloveCuff: named("GloveCuff"))
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
    /// 0...1 of a breath: Tick grows up to 2%. Applied round the whole
    /// figure by `TickView`, so a breath never redraws the parts.
    var breath: Double = 0
    /// Degrees added to the tapping foot.
    var footTap: Double = 0
    /// 0...1 of reaching up and pressing the crown.
    var crownTap: Double = 0
    /// How far the plain brows lift, in Tick units.
    var browLift: Double = 0
    /// 0...1 of the z's floating up and away.
    var zeeRise: Double = 0
    /// 0...1 of the star's twinkle.
    var twinkle: Double = 0
    /// 0...1 of the alarm lines' flash: dimmer at 1.
    var alarmFlash: Double = 0
    /// 0...1 of a shrug: hands and shoulders up.
    var shrug: Double = 0

    // Entries, each 0 at rest.
    /// Smaller than full size, as a fraction (0.2 is 80%): popping in.
    var shrink: Double = 0
    /// Squashed wider and lower, 0...1 (applied about the feet).
    var squash: Double = 0
    /// -1...1 of the waving hand's swing.
    var wave: Double = 0
    /// 0...1 of the headphones still above the head, sliding on.
    var headphonesAbove: Double = 0
    /// 0...1 of the gold ring still to sweep round.
    var goldUnswept: Double = 0
    /// 0...1 of the sparkles still to burst out.
    var sparklesIn: Double = 0
    /// 0...1 of the mug still to pop into the hand.
    var mugIn: Double = 0
    /// 0...1 of the star still to drop onto the crown.
    var starAbove: Double = 0

    static let still = TickMotion()
}

/// How much detail fits: hand-made touches only when large, the full pose
/// simplified in between, and just the head when tiny.
enum TickDetail: Equatable, Sendable {
    /// 120 pt and up: an outline a little heavier on one side, the crown
    /// a touch off centre, a faint grain on the face.
    case handmade
    /// The full pose, cleaner, with bolder limbs and props.
    case simplified
    /// Under 40 pt: ring, crown and eyes, plus a mouth from 14 pt. The
    /// smallest is solid shapes only.
    case glyph(mouth: Bool)
    /// Just the face, eyes and mouth, for inside a ring the system draws
    /// (a live countdown on the Lock Screen and in the Dynamic Island).
    case face

    static func fitting(points: Double) -> TickDetail {
        if points >= 120 { return .handmade }
        if points >= 40 { return .simplified }
        return .glyph(mouth: points >= 14)
    }
}

/// Tick, Clockin's mascot: a little cream-and-terracotta kitchen timer
/// whose ring is its own timer and whose crown is the start button. Drawn
/// from its parts (`TickParts`) in a 100-unit square scaled to fit, with
/// the detail picked from the size unless given.
struct TickFigure: View, Equatable {
    var rig: TickRig
    var face: TickFace
    var palette: TickPalette
    var motion: TickMotion = .still
    /// Nil picks the detail from the size it's drawn at.
    var detail: TickDetail? = nil
    var progress: Double

    /// Tick still in a state, as on the character sheet.
    init(pose: TickPose, palette: TickPalette, motion: TickMotion = .still, detail: TickDetail? = nil,
         progress: Double? = nil) {
        var face = TickFace(pose)
        face.blink = motion.blink
        self.init(rig: TickRig(pose), face: face, palette: palette, motion: motion, detail: detail,
                  progress: motion.ring ?? progress ?? pose.sheetProgress)
    }

    /// Tick in any pose and face, for animation.
    init(rig: TickRig, face: TickFace, palette: TickPalette, motion: TickMotion = .still, detail: TickDetail? = nil,
         progress: Double) {
        self.rig = rig
        self.face = face
        self.palette = palette
        self.motion = motion
        self.detail = detail
        self.progress = progress
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            TickParts(rig: rig, face: face, progress: progress,
                      palette: palette, motion: motion, detail: detail ?? .fitting(points: side))
                .scaleEffect(side / 100, anchor: .topLeading)
                .frame(width: side, height: side, alignment: .topLeading)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
