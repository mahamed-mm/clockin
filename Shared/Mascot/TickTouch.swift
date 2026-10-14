import CoreGraphics

/// What a touch on Tick does.
enum TickTouch {
    /// Where on Tick the finger landed.
    enum Region: Equatable { case crown, body }

    enum Action: Equatable {
        /// Stops the ringing alarm.
        case dismissAlarm
        /// The crown is the start button: start, pause or resume.
        case crown
        /// A quick squish and a giggle.
        case poke
    }

    /// How long a poke's giggle lasts.
    static let pokeLength = 0.6

    /// While the alarm rings any touch stops it; otherwise the crown works
    /// the timer (when it may) and the body giggles.
    static func action(for region: Region, pose: TickPose, crownWorks: Bool) -> Action {
        if pose == .ringing { return .dismissAlarm }
        if region == .crown, crownWorks { return .crown }
        return .poke
    }

    /// The crown's centre, in Tick units, for a pose.
    static func crownCenter(_ rig: TickRig) -> CGPoint {
        let ringTop = rig.centerY - TickLook.radius - TickLook.rimWidth / 2
        return rotated(CGPoint(x: 50, y: ringTop - 11), by: rig.lean, about: CGPoint(x: 50, y: rig.pivotY))
    }

    /// The body's centre, in Tick units.
    static func bodyCenter(_ rig: TickRig) -> CGPoint {
        rotated(CGPoint(x: 50, y: rig.centerY), by: rig.lean, about: CGPoint(x: 50, y: rig.pivotY))
    }

    private static func rotated(_ point: CGPoint, by degrees: Double, about pivot: CGPoint) -> CGPoint {
        let a = degrees * .pi / 180
        let dx = point.x - pivot.x, dy = point.y - pivot.y
        return CGPoint(x: pivot.x + dx * cos(a) - dy * sin(a), y: pivot.y + dx * sin(a) + dy * cos(a))
    }
}

extension TickPose {
    /// What Tick is doing, for VoiceOver.
    var spokenState: String {
        switch self {
        case .ready: String(localized: "Ready")
        case .working: String(localized: "Focusing")
        case .waiting: String(localized: "Paused")
        case .done: String(localized: "Done")
        case .onBreak: String(localized: "On a break")
        case .ringing: String(localized: "Alarm ringing")
        case .hello: String(localized: "Saying hello")
        case .interrupted: String(localized: "Stopped early")
        case .streak: String(localized: "A set of four done")
        case .sleeping: String(localized: "Asleep")
        }
    }
}
