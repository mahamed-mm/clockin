import SwiftData
import SwiftUI

enum FocusLayout {
    /// The dial's side: the height left after everything around it, never
    /// wider than the column and never under `minimum`. When the minimum
    /// doesn't fit, the page scrolls.
    static func dialSide(viewportHeight: CGFloat, chrome: CGFloat, minimum: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(width, max(minimum, viewportHeight - chrome))
    }

    /// The gap between the header, the dial, the slot and the controls:
    /// tighter on a short screen (an iPhone SE), so the dial keeps its room.
    /// The same in every stage, so moving between them never jumps.
    static func spacing(viewportHeight: CGFloat) -> CGFloat {
        viewportHeight > 0 && viewportHeight < 640 ? Space.m : Space.l
    }

    /// A tip at the end of a session only where there's room for one
    /// without squeezing the dial (not on an iPhone SE).
    static func roomForTip(viewportHeight: CGFloat) -> Bool {
        viewportHeight >= 700
    }

    /// Dial beside the controls rather than above them: a wide scene, or one
    /// on its side. `height` includes the keyboard's space, so opening the
    /// name or park field never flips the page.
    static func isWide(width: CGFloat, height: CGFloat) -> Bool {
        width > 640 || width > height * 1.15
    }

    /// The size the page lays out to, and whether it's being held. While
    /// the park field is open, and while the keyboard is still going after
    /// it, the page keeps the size it had before (`current`), so the dial
    /// and Tick stay put and the keyboard covers what's below. A new width
    /// (rotation, a resized scene) or the height coming back lets go.
    static func layoutViewport(measured: CGSize, current: CGSize, held: Bool,
                               fieldOpen: Bool) -> (size: CGSize, held: Bool) {
        let narrower = measured.height < current.height - 0.5
        guard measured.width == current.width, narrower, fieldOpen || held else { return (measured, false) }
        return (current, true)
    }

    /// Where to scroll so `foot` (in the page) sits at the bottom of what's
    /// visible: down only as far as needed, never past the top.
    static func keepInSight(foot: CGFloat, visibleHeight: CGFloat, scrolled: CGFloat) -> CGFloat {
        let needed = foot - visibleHeight
        return needed > scrolled ? needed : min(scrolled, max(0, needed))
    }

    /// How far a held page will scroll back down once the keyboard has gone:
    /// all of it when the page then fits, less when it's still taller.
    static func scrollUnwind(scrolled: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(0, scrolled - max(0, contentHeight - viewportHeight))
    }

    /// Where a parked thought lands: on Tick, where it will be once the page
    /// has scrolled back by `unwind`. Nil when Tick isn't on screen, or
    /// won't be, so the slip fades where it is instead.
    static func slipLanding(tick: CGRect, unwind: CGFloat, window: CGRect) -> CGPoint? {
        guard tick != .zero else { return nil }
        let landing = CGPoint(x: tick.midX, y: tick.minY + tick.height * 0.3 + unwind)
        return window.contains(landing) ? landing : nil
    }
}

/// Setting the length by dragging the knob round the dial. The face is a
/// 60-minute kitchen timer: 12 o'clock is 0 and 60, one tick a minute.
enum DialLength {
    /// The angle of a touch from the dial's centre, in radians clockwise
    /// from 12 o'clock (0..<2π).
    static func angle(of point: CGPoint, around center: CGPoint) -> Double {
        let angle = atan2(Double(point.x - center.x), Double(center.y - point.y))
        return angle < 0 ? angle + 2 * .pi : angle
    }

    /// The whole face: 60 minutes round, set or running.
    static let face: TimeInterval = 60 * 60

    /// How far round the arc reaches with `remaining` left, so a running
    /// session unwinds from where the knob was set. Full past an hour.
    static func arcValue(remaining: TimeInterval) -> Double {
        min(1, max(0, remaining / face))
    }

    /// The angle the knob sits at for `minutes`.
    static func angle(forMinutes minutes: Int) -> Double {
        Double(minutes) / 60 * 2 * .pi
    }

    /// Whole minutes on the dial for a touch at `angle`, snapped to five.
    /// Crossing 12 o'clock from `previous` holds at the end the finger came
    /// from, so 60 never jumps to 5 or back.
    static func minutes(atAngle angle: Double, previous: Int) -> Int {
        let range = SessionLength.minuteRange
        let raw = angle / (2 * .pi) * 60
        let step = Double(SessionLength.minuteStep)
        let snapped = Int((raw / step).rounded() * step)
        let minutes = min(max(snapped, range.lowerBound), range.upperBound)
        if abs(minutes - previous) > 30 {
            return previous > 30 ? range.upperBound : range.lowerBound
        }
        return minutes
    }

    /// Where the knob sits on a dial of `side` points, set to `minutes`.
    static func knobPoint(minutes: Int, side: CGFloat) -> CGPoint {
        let radius = side / 2 * RetroDial.arcRadiusRatio(showsTicks: true)
        let angle = angle(forMinutes: minutes)
        return CGPoint(x: side / 2 + radius * sin(angle), y: side / 2 - radius * cos(angle))
    }

    /// How big the knob's touch target is: the drawn knob, never under 44 points.
    static func grabSize(side: CGFloat) -> CGFloat {
        max(44, side * 0.16)
    }
}

extension View {
    /// Keeps `height` up to date with this view's laid-out height.
    func measuredHeight(_ height: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height.wrappedValue = $0 }
    }
}

/// While a session runs untouched, everything round the dial fades back so
/// only the countdown and Pause stand out. A touch brings it all back.
enum StepBack {
    /// How long after the last touch the screen steps back.
    static let delay: TimeInterval = 8
    /// How far the pieces round the dial fade.
    static let opacity = 0.25

    /// When the screen may be stepped back: from `delay` after the last touch
    /// until the controls are wanted again, when "+5 min" can appear in the
    /// last minutes of focus, or when a break ends. Nil when nothing runs,
    /// while paused, and with VoiceOver or Switch Control, which move
    /// through the controls.
    static func window(for session: ActiveSession?, lastTouch: Date, assistive: Bool) -> DateInterval? {
        guard !assistive, let session, let end = session.endDate else { return nil }
        let wanted = session.phase == .focus ? end.addingTimeInterval(-SessionEngine.extensionStep) : end
        let start = lastTouch.addingTimeInterval(delay)
        guard start < wanted else { return nil }
        return DateInterval(start: start, end: wanted)
    }
}

/// First-launch teaching, done by the screen itself: a ghost thumb on the
/// dial until the length is first set or a session starts, and one closing
/// line after the very first session. Each shows once.
enum Onboarding {
    static let dialHintKey = "onboarding.dialHint"
    static let welcomeKey = "onboarding.firstFinish"

    /// At most two saved sessions: enough to tell a first launch and a first finish.
    static var firstSessions: FetchDescriptor<FocusRecord> {
        var descriptor = FetchDescriptor<FocusRecord>()
        descriptor.fetchLimit = 2
        return descriptor
    }

    /// While nothing has ever been saved, so people updating with History
    /// never see it.
    static func showsDialHint(seen: Bool, savedSessions: Int, stage: SessionStage) -> Bool {
        guard !seen, savedSessions == 0, case .idle = stage else { return false }
        return true
    }

    /// After the first session ever: the one just finished is all History has.
    static func showsWelcome(seen: Bool, savedSessions: Int, stage: SessionStage) -> Bool {
        guard !seen, savedSessions <= 1, case .focusComplete = stage else { return false }
        return true
    }

    /// When Tick was last on screen, for its hello after a week away.
    static let tickLastSeenKey = "tick.lastSeen"

    #if DEBUG
    /// `-ResetOnboarding`, or the Dev menu: shows the hints again.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: dialHintKey)
        UserDefaults.standard.removeObject(forKey: welcomeKey)
        // Tick says hello again too.
        UserDefaults.standard.removeObject(forKey: tickLastSeenKey)
    }
    #endif
}
