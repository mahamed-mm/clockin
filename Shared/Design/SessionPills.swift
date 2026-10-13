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
    @Environment(\.colorSchemeContrast) private var contrast

    /// Pure state for pill `index`; kept separate so it can be unit tested.
    static func state(index: Int, completed: Int, inProgress: Bool) -> PillState {
        if index < completed { return .filled(colorIndex: index % setSize) }
        if index == completed && inProgress { return .current }
        return .empty
    }

    /// Sessions beyond the set of four, shown as "+N".
    static func extra(completed: Int) -> Int { max(0, completed - setSize) }

    static func caption(completed: Int) -> String {
        Copy.pillsCaption(completed: completed, setSize: setSize)
    }

    private static let colors: [Color] = Retro.stripes.reversed()

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
        pill(Self.state(index: index, completed: completed, inProgress: inProgress))
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
                .fill(Self.colors[colorIndex])
                .widgetAccentable()
        case .current:
            Capsule()
                .strokeBorder(tint, lineWidth: max(1.5, pillHeight * 0.25))
                .widgetAccentable()
        case .empty:
            // Faint by design, but outlined clearly when Increase Contrast is on.
            Capsule()
                .strokeBorder(Retro.ink.opacity(contrast == .increased ? 0.65 : 0.3),
                              lineWidth: contrast == .increased ? 1.5 : 1)
        }
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
