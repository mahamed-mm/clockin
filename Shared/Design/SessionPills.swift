import SwiftUI
import WidgetKit

/// Today's progress through a set of four focus sessions: one pill per
/// session. Completed sessions fill in the 70s stripe colours; the session in
/// progress is outlined in the phase tint. Filled vs. outlined is a shape
/// difference, so it still reads in StandBy's red night mode and in tinted
/// widget rendering where colour is flattened.
struct SessionPills: View {
    enum PillState: Equatable {
        case filled(colorIndex: Int)
        case current
        case empty
    }

    static let setSize = TimerPlan.sessionsPerSet

    let completed: Int
    /// True while a focus phase runs (breaks don't count toward the set).
    var inProgress = false
    var pillWidth: CGFloat = 22
    var pillHeight: CGFloat = 6
    var spacing: CGFloat = 4
    /// `.vertical` stacks the pills bottom-up, like a gauge filling.
    var axis: Axis = .horizontal
    /// Shows "2 of 4 today" after the pills.
    var showsCaption = false
    var tint: Color = Retro.orange
    /// A pill filling as its session completes: which, and how full (0...1).
    /// Only the app passes one; widgets and the Live Activity stay still.
    var fill: (index: Int, level: Double)? = nil
    /// The next session's pill outlined, pulsing once: up next, not yet in progress.
    var upNext = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// Pure state for pill `index`; kept separate so it can be unit tested.
    static func state(index: Int, completed: Int, inProgress: Bool) -> PillState {
        if index < completed { return .filled(colorIndex: index % setSize) }
        if index == completed && inProgress { return .current }
        return .empty
    }

    /// The in-progress pill's outline. Already a different shape from a
    /// filled one; with Differentiate Without Color it's also dashed, so it
    /// can't be mistaken for an empty one.
    static func currentStroke(pillHeight: CGFloat, differentiateWithoutColor: Bool) -> StrokeStyle {
        let width = max(1.5, pillHeight * 0.25)
        guard differentiateWithoutColor else { return StrokeStyle(lineWidth: width) }
        return StrokeStyle(lineWidth: width, lineCap: .round, dash: [pillHeight * 0.5, pillHeight * 0.6])
    }

    /// The pill to fill when the count goes from `old` to `new`: only one
    /// session more, just completed (not a launch, a restore or an undo).
    static func fillingPill(from old: Int, to new: Int, justCompleted: Bool) -> Int? {
        guard justCompleted, new == old + 1, old < setSize else { return nil }
        return old
    }

    /// Sessions beyond the set of four, shown as "+N".
    static func extra(completed: Int) -> Int { max(0, completed - setSize) }

    static func caption(completed: Int) -> String {
        Copy.pillsCaption(completed: completed, setSize: setSize)
    }

    var body: some View {
        Group {
            if axis == .vertical {
                VStack(spacing: spacing) {
                    ForEach((0..<Self.setSize).reversed(), id: \.self) { index in
                        pillView(index)
                    }
                    if Self.extra(completed: completed) > 0 {
                        Text(verbatim: "+\(Self.extra(completed: completed))")
                            .font(.retro(.label))
                            .foregroundStyle(Retro.inkSoft)
                    }
                }
            } else {
                horizontal
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.pillsSpoken(completed: completed, setSize: Self.setSize, inProgress: inProgress))
    }

    private func pillView(_ index: Int) -> some View {
        let filling = fill.map { $0.index == index } ?? false
        let next = upNext && !inProgress && index == completed
        // One shape whatever happens, so a pill that starts filling doesn't cross-fade.
        return ZStack {
            // Still outlined as the session in progress while it fills.
            pill(filling || next ? .current
                 : Self.state(index: index, completed: completed, inProgress: inProgress))
                .modifier(PulseOnce(active: next))
            if let fill, filling {
                Capsule()
                    .fill(Retro.setColor(position: index))
                    .opacity(reduceMotion ? fill.level : 1)
                    .mask { LiquidFill(level: reduceMotion ? 1 : fill.level) }
                    .widgetAccentable()
            }
        }
        .frame(width: pillWidth, height: pillHeight)
    }

    private var horizontal: some View {
        HStack(spacing: spacing * 2) {
            HStack(spacing: spacing) {
                ForEach(0..<Self.setSize, id: \.self) { index in
                    pillView(index)
                }
            }
            if showsCaption {
                Text(Self.caption(completed: completed))
                    .font(.retro(.meta))
                    .monospacedDigit()
                    .foregroundStyle(Retro.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if Self.extra(completed: completed) > 0 {
                Text(verbatim: "+\(Self.extra(completed: completed))")
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
            }
        }
    }

    @ViewBuilder
    private func pill(_ state: PillState) -> some View {
        switch state {
        case .filled(let colorIndex):
            Capsule()
                .fill(Retro.setColor(position: colorIndex))
                .widgetAccentable()
        case .current:
            Capsule()
                .strokeBorder(tint, style: Self.currentStroke(pillHeight: pillHeight,
                                                              differentiateWithoutColor: differentiateWithoutColor))
                .widgetAccentable()
        case .empty:
            // Faint by design, but outlined clearly when Increase Contrast is on.
            Capsule()
                .strokeBorder(Retro.ink.opacity(contrast == .increased ? 0.65 : 0.3),
                              lineWidth: contrast == .increased ? 1.5 : 1)
        }
    }
}

/// One gentle swell, when the pill comes up next; a fade with Reduce Motion.
private struct PulseOnce: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: active) { view, value in
            if reduceMotion {
                view.opacity(value)
            } else {
                view.scaleEffect(value)
            }
        } keyframes: { [active, reduceMotion] _ in
            if active {
                CubicKeyframe(reduceMotion ? 0.3 : 1.35, duration: 0.35)
                CubicKeyframe(1.0, duration: 0.5)
            } else {
                LinearKeyframe(1.0, duration: 0.01)
            }
        }
    }
}

/// A pill filling up from the left like liquid, its edge a slight wave
/// that settles flat as it fills.
struct LiquidFill: Shape {
    /// 0 empty to 1 full.
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    /// How far the edge bulges, as a fraction of the height: none empty or full.
    static func amplitude(at level: Double) -> Double {
        0.22 * sin(.pi * min(1, max(0, level)))
    }

    func path(in rect: CGRect) -> Path {
        let level = min(1, max(0, level))
        guard level > 0 else { return Path() }
        guard level < 1 else { return Path(rect) }
        let wave = Self.amplitude(at: level) * rect.height
        // Room for the wave, so it starts off the left edge and ends past the right.
        let edge = rect.minX - wave + (rect.width + 2 * wave) * level
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        let steps = 12
        for i in 0...steps {
            let y = rect.minY + rect.height * Double(i) / Double(steps)
            // The wave slides along as it fills.
            let x = edge + wave * sin(2 * .pi * (Double(i) / Double(steps)) + 6 * .pi * level)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        SessionPills(completed: 0, inProgress: true, showsCaption: true)
        SessionPills(completed: 2, inProgress: true, showsCaption: true)
        SessionPills(completed: 4, showsCaption: true)
        SessionPills(completed: 6)
    }
    .padding(30)
    .background(PaperBackground())
}
