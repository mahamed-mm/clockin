import SwiftUI

/// Where a day's sessions sit on its ribbon: 06:00 to midnight, reaching
/// back to the hour of anything earlier. Pure, so it can be tested.
struct DayRibbonLayout: Equatable {
    struct Session: Equatable {
        var id: UUID
        var name: String
        var startedAt: Date
        var completedAt: Date
        var seconds: TimeInterval
        var countsAsFull: Bool
    }

    struct Block: Equatable, Identifiable {
        var id: UUID
        var name: String
        var startedAt: Date
        var completedAt: Date
        /// Its place in the day's set of four, from 0; nil for a session that
        /// ended under half its plan and doesn't count.
        var position: Int?
        var x: CGFloat
        var width: CGFloat
    }

    /// Hours from the start of the day.
    var hours: ClosedRange<Double>
    var blocks: [Block]

    /// The narrowest a block gets, so a short session still shows.
    static let minimumWidth: CGFloat = 6
    /// How far from a block a tap still opens it.
    static let reach: CGFloat = 22
    static let marks = [6, 12, 18]

    init(sessions: [Session], day: Date, calendar: Calendar, width: CGFloat) {
        let start = calendar.startOfDay(for: day)
        func hour(_ date: Date) -> Double { date.timeIntervalSince(start) / 3_600 }
        let sorted = sessions.sorted { $0.completedAt < $1.completedAt }
        let earliest = sorted.map { max(0, hour($0.startedAt)) }.min() ?? 6
        let latest = sorted.map { hour($0.completedAt) }.max() ?? 24
        let lower = min(6, earliest.rounded(.down)), upper = max(24, latest.rounded(.up))
        hours = lower...upper
        func x(_ hour: Double) -> CGFloat { CGFloat((min(max(hour, lower), upper) - lower) / (upper - lower)) * width }
        var full = 0
        var blocks: [Block] = []
        for session in sorted {
            let left = x(hour(session.startedAt)), right = x(hour(session.completedAt))
            let position = session.countsAsFull ? full % TimerPlan.sessionsPerSet : nil
            if session.countsAsFull { full += 1 }
            let blockWidth = max(Self.minimumWidth, right - left)
            blocks.append(Block(id: session.id, name: session.name, startedAt: session.startedAt,
                                completedAt: session.completedAt, position: position,
                                x: max(0, min(left, width - blockWidth)), width: blockWidth))
        }
        self.blocks = blocks
    }

    /// Where an hour mark sits.
    func x(ofHour hour: Int, width: CGFloat) -> CGFloat {
        CGFloat((Double(hour) - hours.lowerBound) / (hours.upperBound - hours.lowerBound)) * width
    }

    /// The block a tap at `x` means: the one under it, else the nearest
    /// within reach, the later one on a tie.
    func block(nearest x: CGFloat) -> Block? {
        var best: (block: Block, distance: CGFloat)?
        for block in blocks {
            let distance = max(0, block.x - x, x - (block.x + block.width))
            guard distance <= Self.reach else { continue }
            if best == nil || distance <= best!.distance { best = (block, distance) }
        }
        return best?.block
    }
}

/// The selected day as a line of time: each session a block from its start
/// to its end, coloured by its place in the day's set of four.
struct DayRibbon: View {
    let title: String
    let sessions: [DayRibbonLayout.Session]
    let day: Date
    let calendar: Calendar
    /// Opens the session's card.
    let open: (UUID) -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 26
    @State private var width: CGFloat = 0
    @State private var appeared = false

    private var still: Bool { services.power.isConstrained }

    var body: some View {
        let layout = DayRibbonLayout(sessions: sessions, day: day, calendar: calendar, width: width)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title).retroLabel()
                Spacer()
                Text(TimeFormat.duration(sessions.reduce(0) { $0 + $1.seconds }))
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
                    .opacity(sessions.isEmpty ? 0 : 1)
            }
            .accessibilityElement(children: .combine)
            bar(layout)
            marks(layout)
        }
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = still
            withTransaction(transaction) { appeared = true }
        }
    }

    private func bar(_ layout: DayRibbonLayout) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Retro.ink.opacity(0.06))
            ForEach(DayRibbonLayout.marks, id: \.self) { hour in
                Rectangle()
                    .fill(Retro.ink.opacity(0.12))
                    .frame(width: 1)
                    .offset(x: layout.x(ofHour: hour, width: width))
                    .accessibilityHidden(true)
            }
            if sessions.isEmpty {
                Text("No sessions")
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(layout.blocks.enumerated()), id: \.element.id) { index, block in
                blockView(block)
                    .frame(width: block.width)
                    .scaleEffect(x: appeared || reduceMotion ? 1 : 0.001, anchor: .leading)
                    .opacity(appeared ? 1 : 0)
                    .animation((reduceMotion ? Motion.calm(true) : Motion.wind(false))
                        .delay(Motion.stagger(index, reduceMotion)), value: appeared)
                    .offset(x: block.x)
                    .accessibilityElement()
                    .accessibilityLabel(Copy.ribbonBlock(name: Copy.displayName(block.name),
                                                         from: block.startedAt, to: block.completedAt))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityInputLabels([Copy.displayName(block.name)])
                    .accessibilityAction { open(block.id) }
            }
        }
        .frame(height: barHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(.rect)
        .onTapGesture { location in
            if let block = layout.block(nearest: location.x) { open(block.id) }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func blockView(_ block: DayRibbonLayout.Block) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        if let position = block.position {
            shape
                .fill(Retro.setColor(position: position))
                .overlay {
                    if contrast == .increased { shape.strokeBorder(Retro.ink, lineWidth: 1) }
                }
                .overlay {
                    if differentiateWithoutColor, block.width >= 18 {
                        Text(verbatim: "\(position + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Retro.ink)
                    }
                }
        } else {
            shape.strokeBorder(Retro.ink.opacity(0.6), lineWidth: 1)
        }
    }

    /// 6, 12 and 18 under the bar; only noon at the largest text sizes.
    private func marks(_ layout: DayRibbonLayout) -> some View {
        let hours = dynamicTypeSize.isAccessibilitySize ? [12] : DayRibbonLayout.marks
        return ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { hour in
                Text(label(hour))
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
                    .fixedSize()
                    .alignmentGuide(.leading) { $0.width / 2 - layout.x(ofHour: hour, width: width) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func label(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour())
    }
}
