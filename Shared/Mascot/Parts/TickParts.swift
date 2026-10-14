import SwiftUI

/// Tick, put together from its parts in a 100-unit square, back to front:
/// back limbs, ring track, time-left arc, face, cheeks, eyes, mouth,
/// eyebrow hand, front limbs, the arc's cap, crown, then props and effects.
/// The headphones' band and the alarm's vibration go behind the body, as
/// they wrap round it.
///
/// The rig and face animate: change them inside an animation and every
/// part springs to the new pose together.
struct TickParts: View, Animatable {
    var rig: TickRig
    var face: TickFace
    var progress: Double
    var palette: TickPalette
    var motion: TickMotion = .still
    var detail: TickDetail

    var animatableData: AnimatablePair<TickRig.AnimatableData, AnimatablePair<TickFace.AnimatableData, Double>> {
        get { AnimatablePair(rig.animatableData, AnimatablePair(face.animatableData, progress)) }
        set {
            rig.animatableData = newValue.first
            face.animatableData = newValue.second.first
            progress = newValue.second.second
        }
    }

    var body: some View {
        let look = TickLook(rig: rig, face: face, progress: progress, palette: palette, motion: motion, detail: detail)
        ZStack(alignment: .topLeading) {
            if case .glyph(let mouth) = detail {
                TickGlyphPart(look: look, mouth: mouth)
            } else if detail == .face {
                TickFacePart(look: look)
            } else {
                TickGroundPart(look: look)
                TickLegsPart(look: look)
                    .modifier(BodyMotion(look: look, follow: rig.legFollow))
                ZStack(alignment: .topLeading) {
                    TickBackPropsPart(look: look)
                    TickRingTrackPart(look: look)
                    TickRingArcPart(look: look)
                    TickRingRimPart(look: look)
                    TickCheeksPart(look: look)
                    TickEyesPart(look: look, center: CGPoint(x: 50 + face.gazeX, y: look.centerY - 3))
                    TickMouthPart(look: look, center: CGPoint(x: 50 + face.gazeX, y: look.centerY + 8))
                    TickBrowsPart(look: look)
                    TickBrowHandPart(look: look)
                    TickHeadphoneCupsPart(look: look)
                    TickArmsPart(look: look)
                    TickRingCapPart(look: look)
                    TickCrownPart(look: look)
                    TickMugPart(look: look)
                    TickEffectsPart(look: look)
                    TickSweatPart(look: look)
                }
                .modifier(BodyMotion(look: look, follow: 1))
            }
        }
        .frame(width: 100, height: 100, alignment: .topLeading)
    }
}

/// The body's lean and squash about its pivot, plus the bob and the
/// alarm's shake. `follow` takes part of it, for legs that stay put.
private struct BodyMotion: ViewModifier {
    let look: TickLook
    let follow: Double

    func body(content: Content) -> some View {
        let rig = look.rig
        let anchor = UnitPoint(x: 0.5, y: rig.pivotY / 100)
        content
            .scaleEffect(x: 1 + (rig.scaleX - 1) * follow, y: 1 + (rig.scaleY - 1) * follow, anchor: anchor)
            .rotationEffect(.degrees((rig.lean + look.motion.lean) * follow), anchor: anchor)
            .offset(x: 1.5 * look.motion.tremble * follow, y: look.motion.bob * follow)
    }
}
