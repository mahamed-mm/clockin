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
