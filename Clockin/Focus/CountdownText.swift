import SwiftUI

/// The countdown's digits, the only part of a screen that follows the
/// clock every second. Its own view, so each second redraws this text and
/// nothing around it.
struct CountdownText: View {
    /// Nil before a session: then it reads `idle`, and stays put.
    let session: ActiveSession?
    var idle: TimeInterval = 0
    let size: CGFloat
    var tracking: CGFloat = -1
    var ink: Color = Retro.ink
    /// Reads the time left as words, for a countdown that is its own element.
    var speaks = false
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LiveTimeline(TickSchedule(countdownEnd: session?.endDate)) { context in
            let remaining = session?.remaining(at: context.date) ?? idle
            let clock = TimeFormat.clock(remaining)
            Text(clock)
                .font(.retroDisplay(size: size))
                .tracking(tracking)
                .foregroundStyle(ink)
                .retroNumber(countsDown: true)
                .animation(services.power.isConstrained ? nil : Motion.snappy(reduceMotion), value: clock)
                .modifier(BlinkWhilePaused(active: session?.isPaused == true))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel(speaks ? TimeFormat.spoken(remaining) : clock)
        }
    }
}
