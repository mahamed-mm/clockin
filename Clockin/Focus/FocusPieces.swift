import SwiftData
import SwiftUI

// MARK: - Header

/// Serif phase title with a time-range line underneath (Tiimo-style).
struct FocusHeader: View {
    let stage: SessionStage

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.retro(.title))
                    .foregroundStyle(Retro.ink)
                    .contentTransition(.numericText())
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(meta(at: context.date))
                            .font(.retro(.meta))
                            .foregroundStyle(Retro.inkSoft)
                            .contentTransition(.numericText())
                    }
                    Text("·").foregroundStyle(Retro.inkSoft.opacity(0.6))
                    TodayChip()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            #if DEBUG
            // Demo data is for screenshots, so keep developer chrome out of them.
            if !DemoData.isRequested {
                HStack(spacing: 10) {
                    TestTimersBadge()
                    DevMenu().foregroundStyle(Retro.inkSoft)
                }
                .padding(.top, 10)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch stage {
        case .idle: "Focus"
        case .active(let session): session.phase == .focus ? "Focus" : "Break"
        case .focusComplete: "Well done"
        }
    }

    private func meta(at now: Date) -> String {
        switch stage {
        case .idle:
            return "\(TimeFormat.duration(Durations.duration(for: .focus))) session"
        case .active(let session):
            if session.isPaused {
                return "Paused · \(TimeFormat.clock(session.remaining(at: now))) left"
            }
            let end = session.endDate ?? now
            return session.phase == .focus
                ? TimeFormat.range(end.addingTimeInterval(-session.plannedDuration), end)
                : "Until \(TimeFormat.time(end))"
        case .focusComplete:
            return "Take a breather"
        }
    }
}

/// "Today 50 min", live from SwiftData.
struct TodayChip: View {
    @Query private var records: [FocusRecord]

    init(day: Date = .now) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        _records = Query(filter: #Predicate<FocusRecord> { $0.completedAt >= start && $0.completedAt < end })
    }

    var body: some View {
        let seconds = records.reduce(0) { $0 + $1.focusSeconds }
        Text("Today \(TimeFormat.duration(seconds))")
            .font(.retro(.meta))
            .foregroundStyle(Retro.inkSoft)
            .contentTransition(.numericText())
            .accessibilityLabel("Today: \(TimeFormat.duration(seconds)) of focus")
    }
}

/// Today's session pills, live from SwiftData.
struct TodaySessionPills: View {
    let inProgress: Bool
    var tint: Color = Retro.orange
    /// Scales the pills with the dial.
    var scale: CGFloat = 1
    @Query private var records: [FocusRecord]

    init(inProgress: Bool, tint: Color = Retro.orange, scale: CGFloat = 1) {
        self.inProgress = inProgress
        self.tint = tint
        self.scale = scale
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        _records = Query(filter: #Predicate<FocusRecord> { $0.completedAt >= start && $0.completedAt < end })
    }

    var body: some View {
        SessionPills(completed: records.count, inProgress: inProgress,
                     pillWidth: 20 * scale, pillHeight: 5.5 * scale, spacing: 4 * scale, tint: tint)
            .animation(.smooth, value: records.count)
    }
}

// MARK: - Dial

/// The dial with its countdown. The arc shows the time *left*, like a kitchen
/// timer: it winds up on start, unwinds as time passes, rewinds on cancel,
/// and closes into a full ring on completion.
struct DialFace: View {
    let stage: SessionStage
    let size: CGFloat
    /// Increments when a focus session completes.
    let celebration: Int
    /// Shows the phase symbol instead of the countdown, for layouts that
    /// print the countdown elsewhere (bedside mode).
    var showsCountdown = true
    /// Today's session pills under the countdown (bedside shows its own).
    var showsPills = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let session = activeSession
            let remaining = session?.remaining(at: now) ?? Durations.duration(for: .focus)
            let value = arcValue(session: session, now: now)

            ZStack {
                Sunburst(trigger: celebration)
                    .frame(width: size, height: size)

                RetroDial(value: value, tint: tint, glowTint: glowTint)
                    .saturation(session?.isPaused == true ? 0.45 : 1)
                    // Inner modifier wins when the stage changes: spring the arc.
                    .animation(Motion.wind(reduceMotion), value: stageKey)
                    // Otherwise creep linearly between one-second ticks.
                    .animation(.linear(duration: 1), value: value)
                    .keyframeAnimator(initialValue: 1.0, trigger: celebration) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { [speed = Motion.speed, reduceMotion] _ in
                        CubicKeyframe(1.0, duration: 0.05 * speed)
                        CubicKeyframe(reduceMotion ? 1.0 : 1.035, duration: 0.18 * speed)
                        SpringKeyframe(1.0, duration: 0.6 * speed)
                    }

                if case .idle = stage {
                    IdleKnobGlow(size: size)
                        .transition(.opacity)
                }

                center(remaining: remaining, session: session)
                    .padding(size * 0.25)
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(remaining: remaining, session: session))
        }
    }

    @ViewBuilder
    private func center(remaining: TimeInterval, session: ActiveSession?) -> some View {
        VStack(spacing: size * 0.025) {
            Text(status(session)).retroLabel()
                .contentTransition(.opacity)
            if !showsCountdown, let session {
                Image(systemName: session.phase.symbol)
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(Retro.ink)
                    .contentTransition(.symbolEffect(.replace))
            } else if case .focusComplete = stage {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.2))
                    .foregroundStyle(Retro.orange, Retro.mustard)
                    .symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: celebration)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                let clock = TimeFormat.clock(remaining)
                Text(clock)
                    .font(.retroDisplay(size: size * 0.18))
                    .tracking(-1)
                    .foregroundStyle(Retro.ink)
                    .retroNumber(countsDown: true)
                    .animation(Motion.snappy(reduceMotion), value: clock)
                    .modifier(BlinkWhilePaused(active: session?.isPaused == true))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            if showsPills {
                TodaySessionPills(inProgress: session?.phase == .focus,
                                  tint: tint, scale: size / 320)
                    .padding(.top, size * 0.02)
            }
        }
    }

    // MARK: Derived state

    private var activeSession: ActiveSession? {
        if case .active(let session) = stage { return session }
        return nil
    }

    /// Changes only when the stage changes, not every second.
    private var stageKey: String {
        switch stage {
        case .idle: "idle"
        case .active(let s): "\(s.id)-\(s.phase)-\(s.isPaused)"
        case .focusComplete: "complete"
        }
    }

    private var tint: Color {
        switch stage {
        case .idle: Retro.orange
        case .active(let session): Retro.tint(for: session.phase)
        case .focusComplete: Retro.orange
        }
    }

    private var glowTint: Color {
        if let session = activeSession { return Retro.glow(for: session.phase) }
        return Retro.mustard
    }

    private func arcValue(session: ActiveSession?, now: Date) -> Double {
        switch stage {
        case .idle: 0
        case .active(let s): s.plannedDuration > 0 ? s.remaining(at: now) / s.plannedDuration : 0
        case .focusComplete: 1
        }
    }

    private func status(_ session: ActiveSession?) -> String {
        switch stage {
        case .idle: "Ready"
        case .active(let s): s.isPaused ? "Paused" : "Running"
        case .focusComplete: "Complete"
        }
    }

    private func accessibilityText(remaining: TimeInterval, session: ActiveSession?) -> String {
        switch stage {
        case .idle: "Ready, \(TimeFormat.duration(remaining)) session"
        case .active(let s): "\(s.phase.label)\(s.isPaused ? ", paused" : ""), \(TimeFormat.spoken(remaining))"
        case .focusComplete: "Focus complete"
        }
    }
}

/// A slow "breathing" halo on the knob while the timer waits to start.
private struct IdleKnobGlow: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let line = size * 0.075
        let halo = Circle()
            .fill(Retro.orange)
            .frame(width: line * 2.4, height: line * 2.4)
            .blur(radius: line * 0.55)
            .offset(y: -size / 2 * RetroDial.arcRadiusRatio(showsTicks: true))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        if reduceMotion {
            halo.opacity(0.2)
        } else {
            halo.phaseAnimator([0.08, 0.38]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 3) }
        }
    }
}

// MARK: - Session chip

/// What you're working on, shown while a session runs.
struct SessionChip: View {
    let session: ActiveSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.phase == .focus ? "book.closed.fill" : "cup.and.saucer.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Retro.tint(for: session.phase))
                .contentTransition(.symbolEffect(.replace))
            Text(session.phase == .focus ? session.name : "Break after \(session.name)")
                .font(.retro(.headline))
                .foregroundStyle(Retro.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Alert hint

/// One quiet line under Start, only when the end alert can't reach the user,
/// or before the first Start, which is when permission is asked for.
struct AlertHint: View {
    let status: AlertStatus
    /// The status whose hint was dismissed. A different problem shows again.
    @AppStorage("alertHint.dismissed") private var dismissed = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let message, dismissed != key {
            HStack(spacing: 8) {
                if let settings {
                    Button(message) { openURL(settings) }
                        .accessibilityHint("Opens Settings")
                    Button { dismissed = key } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("Dismiss")
                } else {
                    Text(message)
                }
            }
            .font(.retro(.meta))
            .foregroundStyle(Retro.inkSoft)
            .buttonStyle(.borderless)
            .multilineTextAlignment(.center)
            .frame(minHeight: 32)
        }
    }

    private var key: String { String(describing: status) }

    private var message: String? {
        switch status {
        case .notAsked: "Clockin will ask once to alert you when time's up."
        case .notificationsOff: "Alerts are off, so the timer can't ring. Turn on"
        case .liveActivitiesOff: "Live Activities are off for Clockin. Turn on"
        case .unknown, .ready: nil
        }
    }

    private var settings: URL? {
        switch status {
        case .notificationsOff: URL(string: UIApplication.openNotificationSettingsURLString)
        case .liveActivitiesOff: URL(string: UIApplication.openSettingsURLString)
        case .unknown, .notAsked, .ready: nil
        }
    }
}

// MARK: - Completion

/// TIDE-style stat trio shown after a focus session completes.
struct CompletionSummary: View {
    let name: String
    @Query private var today: [FocusRecord]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(name: String) {
        self.name = name
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        _today = Query(filter: #Predicate<FocusRecord> { $0.completedAt >= start && $0.completedAt < end },
                       sort: \.completedAt, order: .reverse)
    }

    var body: some View {
        let last = today.first?.focusSeconds ?? Durations.duration(for: .focus)
        let total = today.reduce(0) { $0 + $1.focusSeconds }
        HStack(spacing: 0) {
            stat(TimeFormat.duration(last), "Focused", index: 0)
            divider
            stat(name, "Session", index: 1)
            divider
            stat(TimeFormat.duration(total), "Today", index: 2)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(Retro.ink.opacity(0.12)).frame(width: 1, height: 34)
    }

    private func stat(_ value: String, _ caption: String, index: Int) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.retro(.headline))
                .foregroundStyle(Retro.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption).retroLabel()
        }
        .frame(maxWidth: .infinity)
        .transition(.rise(reduceMotion, delay: 0.25 + 0.06 * Double(index)))
    }

}
