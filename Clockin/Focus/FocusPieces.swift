import SwiftData
import SwiftUI

// MARK: - Header

/// Serif phase title with a time-range line underneath (Tiimo-style).
struct FocusHeader: View {
    let stage: SessionStage
    @Environment(AppServices.self) private var services
    @Environment(SessionEngine.self) private var engine
    @State private var showingSettings = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.retro(.title))
                    .foregroundStyle(Retro.ink)
                    .contentTransition(.numericText())
                    .accessibilityAddTraits(.isHeader)
                // The line only changes on its own when a completion stops
                // being recent; everything else is a stage change.
                TimelineView(TickSchedule(wakeDates: metaChanges)) { context in
                    let meta = Text(meta(at: context.date))
                        .font(.retro(.meta))
                        .foregroundStyle(Retro.inkSoft)
                        .contentTransition(.numericText())
                    // One line when it fits, today's total under it when not.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            meta
                            Text(verbatim: "·").foregroundStyle(Retro.inkSoft.opacity(0.6))
                            TodayChip(day: services.today)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            meta
                            TodayChip(day: services.today)
                        }
                    }
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                #if DEBUG
                // Demo data is for screenshots, so keep developer chrome out of them.
                if !DemoData.isRequested {
                    TestTimersBadge()
                    DevMenu()
                        .frame(width: 44, height: 44)
                }
                #endif
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Settings")
            }
            .foregroundStyle(Retro.inkSoft)
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
        }
    }

    private var title: String {
        switch stage {
        case .idle: Copy.focus
        case .active(let session): session.isLongBreak == true ? Copy.longBreak : session.phase.label
        case .focusComplete(let focus): focus.outcome == .endedEarly ? Copy.endedEarly : Copy.focusComplete
        }
    }

    /// When an unchanged stage's meta line reads differently: a completion
    /// turns old once its break would be over, or at midnight.
    private var metaChanges: [Date] {
        guard case .focusComplete(let focus) = stage else { return [] }
        let breakOver = focus.completedAt.addingTimeInterval(engine.breakLength(after: focus))
        return [breakOver, services.calendar.dayRange(containing: focus.completedAt).upperBound]
    }

    private func meta(at now: Date) -> String {
        switch stage {
        case .idle:
            return String(localized: "\(TimeFormat.duration(services.plan.focus)) session")
        case .active(let session):
            if session.isPaused {
                return String(localized: "Paused · \(TimeFormat.clock(session.remaining(at: now))) left")
            }
            let end = session.endDate ?? now
            return session.phase == .focus
                ? TimeFormat.range(end.addingTimeInterval(-session.plannedDuration), end)
                : String(localized: "Until \(TimeFormat.time(end))")
        case .focusComplete(let focus):
            // An old completion opens quietly, saying when it was.
            return engine.freshness(of: focus, at: now) == .stale
                ? TimeFormat.finished(focus.completedAt, now: now)
                : Copy.breakLine(seconds: engine.breakLength(after: focus))
        }
    }
}

/// "Today 50 min", live from SwiftData plus any sessions waiting to be saved.
/// `day` comes from `AppServices.today`, so the query moves on at midnight.
struct TodayChip: View {
    private let day: Date
    @Query private var records: [FocusRecord]
    @Environment(SessionEngine.self) private var engine

    init(day: Date) {
        self.day = day
        _records = Query(filter: FocusRecord.completed(on: day))
    }

    var body: some View {
        let seconds = TodayStats.rows(saved: records.map(\.row), pending: engine.pendingRecords(on: day)).totalSeconds
        Text("Today \(TimeFormat.duration(seconds))")
            .font(.retro(.meta))
            .foregroundStyle(Retro.inkSoft)
            .contentTransition(.numericText())
            .accessibilityLabel("Today: \(TimeFormat.spokenDuration(seconds)) of focus")
    }
}

/// Today's session pills, live from SwiftData plus any sessions waiting to be saved.
struct TodaySessionPills: View {
    let inProgress: Bool
    private let day: Date
    var tint: Color = Retro.orange
    /// Scales the pills with the dial.
    var scale: CGFloat = 1
    @Query private var records: [FocusRecord]
    @Environment(SessionEngine.self) private var engine

    init(inProgress: Bool, day: Date, tint: Color = Retro.orange, scale: CGFloat = 1) {
        self.inProgress = inProgress
        self.day = day
        self.tint = tint
        self.scale = scale
        _records = Query(filter: FocusRecord.completed(on: day))
    }

    var body: some View {
        let count = TodayStats.rows(saved: records.map(\.row), pending: engine.pendingRecords(on: day)).fullCount
        SessionPills(completed: count, inProgress: inProgress,
                     pillWidth: 20 * scale, pillHeight: 5.5 * scale, spacing: 4 * scale, tint: tint)
            .animation(.smooth, value: count)
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
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let session = activeSession
        // VoiceOver's value changes about once a minute, so it's worked out
        // every ten seconds rather than with the digits.
        TimelineView(TickSchedule(countdownEnd: session?.endDate, interval: 10)) { context in
            dial(session: session)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue(session: session, at: context.date))
                .accessibilityAddTraits(session.map { $0.isPaused ? [] : .updatesFrequently } ?? [])
                .accessibilityActions {
                    if let session {
                        Button(session.isPaused ? String(localized: "Resume") : String(localized: "Pause")) {
                            services.engine.togglePause()
                        }
                    }
                }
                // Bedside prints the countdown beside the dial; read it there, once.
                .accessibilityHidden(!showsCountdown)
        }
    }

    private func dial(session: ActiveSession?) -> some View {
        let constrained = services.power.isConstrained
        return ZStack {
            if !constrained {
                Sunburst(trigger: celebration)
                    .frame(width: size, height: size)
            }

            // Only the arc and the digits follow the clock, and only while
            // the timer runs. The arc moves under half a point a second, so
            // when the phone asks to save power it moves once a minute.
            TimelineView(TickSchedule(countdownEnd: session?.endDate, interval: constrained ? 60 : 1)) { context in
                RetroDial(value: arcValue(session: session, now: context.date), tint: tint, glowTint: glowTint)
                    .saturation(session?.isPaused == true ? 0.45 : 1)
                    // Spring the arc when the stage changes; between ticks it just steps.
                    .animation(Motion.wind(reduceMotion), value: stageKey)
            }
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

            center(session: session)
                .padding(size * 0.25)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func center(session: ActiveSession?) -> some View {
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
                TimelineView(TickSchedule(countdownEnd: session?.endDate)) { context in
                    let clock = TimeFormat.clock(session?.remaining(at: context.date) ?? services.plan.focus)
                    Text(clock)
                        .font(.retroDisplay(size: size * 0.18))
                        .tracking(-1)
                        .foregroundStyle(Retro.ink)
                        .retroNumber(countsDown: true)
                        .animation(services.power.isConstrained ? nil : Motion.snappy(reduceMotion), value: clock)
                        .modifier(BlinkWhilePaused(active: session?.isPaused == true))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .transition(.opacity)
            }
            if showsPills {
                TodaySessionPills(inProgress: session?.phase == .focus, day: services.today,
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
        case .idle: String(localized: "Ready")
        case .active(let s): s.isPaused ? Copy.paused : String(localized: "Running")
        case .focusComplete(let focus):
            focus.outcome == .endedEarly ? String(localized: "Ended") : String(localized: "Complete")
        }
    }

    /// What the dial is. It stays put while the value changes.
    private var accessibilityLabel: String {
        switch stage {
        case .idle: String(localized: "Timer")
        case .active(let s): s.isLongBreak == true ? Copy.longBreak : s.phase.label
        case .focusComplete(let focus): focus.outcome == .endedEarly ? Copy.endedEarly : Copy.focusComplete
        }
    }

    /// "24 minutes left", "Paused, 24 minutes left", "Ready, 25 minutes".
    private func accessibilityValue(session: ActiveSession?, at date: Date) -> String {
        switch stage {
        case .idle:
            return String(localized: "Ready, \(TimeFormat.spokenDuration(services.plan.focus))")
        case .active(let s):
            let left = TimeFormat.spokenTimeLeft(s.remaining(at: date))
            return s.isPaused ? String(localized: "Paused, \(left)") : left
        case .focusComplete:
            return ""
        }
    }
}

/// A slow "breathing" halo on the knob when the timer starts waiting: three
/// breaths, then it rests, so an idle screen draws nothing.
private struct IdleKnobGlow: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppServices.self) private var services
    @State private var breathe = false
    private static let resting = 0.2

    var body: some View {
        let line = size * 0.075
        let halo = Circle()
            .fill(Retro.orange)
            .frame(width: line * 2.4, height: line * 2.4)
            .blur(radius: line * 0.55)
            .offset(y: -size / 2 * RetroDial.arcRadiusRatio(showsTicks: true))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        if reduceMotion || services.power.isConstrained {
            halo.opacity(Self.resting)
        } else {
            halo.keyframeAnimator(initialValue: Self.resting, trigger: breathe) { view, opacity in
                view.opacity(opacity)
            } keyframes: { [speed = Motion.speed] _ in
                CubicKeyframe(0.08, duration: 1.5 * speed)
                CubicKeyframe(0.38, duration: 3 * speed)
                CubicKeyframe(0.08, duration: 3 * speed)
                CubicKeyframe(0.38, duration: 3 * speed)
                CubicKeyframe(0.08, duration: 3 * speed)
                CubicKeyframe(0.38, duration: 3 * speed)
                CubicKeyframe(Self.resting, duration: 1.5 * speed)
            }
            .onAppear { breathe.toggle() }
        }
    }
}

// MARK: - Session chip

/// What you're working on, shown while a session runs. In the last five
/// minutes of focus it offers "+5 min".
struct SessionChip: View {
    let session: ActiveSession
    @Environment(SessionEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Redraws only when "+5 min" appears or goes away.
        let schedule = TickSchedule(wakeDates: engine.controlChanges(after: .now))
        TimelineView(schedule) { context in
            let canExtend = engine.canExtend(at: context.date)
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: session.phase == .focus ? "book.closed.fill" : "cup.and.saucer.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Retro.tint(for: session.phase))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    Text(session.phase == .focus ? Copy.displayName(session.name) : Copy.breakAfter(session.name))
                        .font(.retro(.headline))
                        .foregroundStyle(Retro.ink)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                if canExtend {
                    Button(action: engine.extend) {
                        Text(Copy.extend(seconds: SessionEngine.extensionStep))
                            .font(.retro(.body).weight(.semibold))
                            .foregroundStyle(Retro.orangeText)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Copy.extendSpoken(seconds: SessionEngine.extensionStep))
                    .accessibilityInputLabels([Copy.extendSpoken(seconds: SessionEngine.extensionStep),
                                               Copy.extend(seconds: SessionEngine.extensionStep)])
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, canExtend ? 16 : 22)
            .padding(.vertical, canExtend ? 2 : 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .glassEffect(.regular, in: .capsule)
            .animation(Motion.calm(reduceMotion), value: canExtend)
        }
        .id(schedule)
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
            HStack(spacing: 4) {
                if let settings {
                    Button(message) { openURL(settings) }
                        .accessibilityHint("Opens Settings")
                        // Voice Control: "Tap Turn on", not the whole sentence.
                        .accessibilityInputLabels([String(localized: "Turn on"), message])
                    Button { dismissed = key } label: {
                        // A full 44 pt target, so aiming for the X can't land in Settings.
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
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
            .frame(minHeight: 44)
        }
    }

    private var key: String { String(describing: status) }

    private var message: String? {
        switch status {
        case .notAsked: String(localized: "Clockin will ask once to alert you when time's up.")
        case .notificationsOff: String(localized: "Alerts are off, so the timer can't ring. Turn on")
        case .liveActivitiesOff: String(localized: "Live Activities are off for Clockin. Turn on")
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

// MARK: - Undo

/// "Session cancelled · Undo", shown for a few seconds after something
/// that can be taken back.
struct UndoBar: View {
    let message: String
    let hint: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .foregroundStyle(Retro.inkSoft)
            Text(verbatim: "·")
                .foregroundStyle(Retro.inkSoft.opacity(0.6))
                .accessibilityHidden(true)
            Button(action: undo) {
                Text("Undo")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .fontWeight(.semibold)
            .foregroundStyle(Retro.orangeText)
            .accessibilityHint(hint)
        }
        .font(.retro(.body))
        .buttonStyle(.borderless)
    }
}

// MARK: - Recent names

/// Up to four recent session names under the name field; a tap fills it in.
struct RecentNames: View {
    let typed: String
    let pick: (String) -> Void
    @Query(RecentNames.newestFirst) private var records: [FocusRecord]

    private static var newestFirst: FetchDescriptor<FocusRecord> {
        var descriptor = FetchDescriptor<FocusRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        descriptor.fetchLimit = 30
        return descriptor
    }

    var body: some View {
        let names = HistoryService.recentNames(records.map(\.name), excluding: typed, limit: 4)
        if !names.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        Button { pick(name) } label: {
                            Text(name)
                                .font(.retro(.meta))
                                .foregroundStyle(Retro.ink)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .accessibilityHint(String(localized: "Uses this name"))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Recent names"))
        }
    }
}

// MARK: - Completion

/// TIDE-style stat trio shown after a focus session completes: this
/// session's length and name, and the total for `day`.
struct CompletionSummary: View {
    let focus: CompletedFocus
    private let day: Date
    @Query private var today: [FocusRecord]
    @Environment(SessionEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(focus: CompletedFocus, day: Date) {
        self.focus = focus
        self.day = day
        _today = Query(filter: FocusRecord.completed(on: day))
    }

    var body: some View {
        let total = TodayStats.rows(saved: today.map(\.row), pending: engine.pendingRecords(on: day)).totalSeconds
        HStack(spacing: 0) {
            stat(TimeFormat.duration(focus.focusSeconds), "Focused", index: 0)
            divider
            stat(Copy.displayName(focus.name), "Session", index: 1)
            divider
            stat(TimeFormat.duration(total), "Today", index: 2)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: """
            Focused \(TimeFormat.spokenDuration(focus.focusSeconds)), \(Copy.displayName(focus.name)), \
            today \(TimeFormat.spokenDuration(total))
            """))
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
