import SwiftUI

/// Follows a break's breathing with one number, 0 empty to 1 full, that
/// the render server animates from each turn to the next: the app itself
/// wakes only at the turns. Held still (at half) with Reduce Motion or Low
/// Power Mode, and frozen while the break is paused. `turn` counts halves
/// of breaths, for a tap at each.
struct BreathFollower<Content: View>: View {
    let activity: TickBreak
    var cycle = BreathCycle.standard
    var still = false
    @ViewBuilder var content: (_ fullness: Double, _ turn: Int) -> Content
    @State private var fullness = 0.5
    @State private var turn = 0
    /// Whether the number is already on its way, so a turn needn't place it first.
    @State private var following = false

    var body: some View {
        content(fullness, turn)
            .background {
                // Now first: an explicit timeline draws its first date first, even a later one.
                TimelineView(.explicit([.now] + turns)) { context in
                    Color.clear.onChange(of: context.date, initial: true) { follow(at: context.date) }
                }
            }
            .onChange(of: activity) {
                following = false
                follow(at: .now)
            }
            .onChange(of: still) {
                following = false
                follow(at: .now)
            }
    }

    /// The turns still to come in this break.
    private var turns: [Date] {
        guard !still, !activity.isPaused else { return [] }
        return cycle.turns(after: activity.styleElapsed(at: .now), through: activity.styleLength)
            .compactMap(activity.date(atStyleElapsed:))
    }

    private func follow(at date: Date) {
        let t = activity.styleElapsed(at: date)
        let phase = cycle.phase(at: t)
        turn = phase.index
        guard !still, !activity.isPaused else {
            following = false
            withTransaction(Transaction(animation: nil)) { fullness = still ? 0.5 : cycle.fullness(at: t) }
            return
        }
        let target: Double = phase.breathingIn ? 1 : 0
        let duration = max(0.05, phase.end - t) * Motion.speed
        if following {
            withAnimation(.easeInOut(duration: duration)) { fullness = target }
        } else {
            // Placed where the breath is now, then on its way from there.
            withTransaction(Transaction(animation: nil)) { fullness = cycle.fullness(at: t) }
            following = true
            Task { @MainActor in
                withAnimation(.easeInOut(duration: duration)) { fullness = target }
            }
        }
    }
}
