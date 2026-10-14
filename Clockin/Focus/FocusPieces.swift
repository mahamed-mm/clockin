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
            VStack(alignment: .leading, spacing: Space.xs) {
                // One line always: a long title ("Focus complete") at large
                // text sizes shrinks to fit rather than wrapping or clipping.
                Text(title)
                    .retroFont(.title)
                    .foregroundStyle(Retro.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
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
                        HStack(spacing: Space.xs) {
                            meta
                            Text(verbatim: "·").foregroundStyle(Retro.inkSoft.opacity(0.6))
                            TodayChip(day: services.today)
                        }
                        .lineLimit(1)
                        // Stacked, each may wrap: at large text sizes nothing is cut off.
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            meta
                            TodayChip(day: services.today)
                        }
                    }
                }
            }
            Spacer(minLength: Space.xs)
            HStack(spacing: 0) {
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
                .accessibilityShowsLargeContentViewer { Label("Settings", systemImage: "gearshape") }
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
                return Copy.pausedMeta(at: session.pausedAt, remaining: session.remaining(at: now))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(Motion.calm(reduceMotion), value: count)
    }
}

// MARK: - Dial

/// The dial with its countdown. The arc is the time *left* on a 60-minute
/// face, like a kitchen timer: set it, and it unwinds from there as time
/// passes; it rewinds to the set length on cancel and closes into a full
/// ring on completion.
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
    /// First launch: a ghost thumb shows how the knob turns.
    var teaches = false
    /// Tick, leaning on the dial's lower right.
    var showsMascot = true
    /// What Tick's crown does, and its name for VoiceOver.
    var crown: (label: String, action: () -> Void)? = nil
    @AppStorage(Onboarding.dialHintKey) private var dialHintSeen = false
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The length under the finger while the knob is dragged; saved on release.
    @State private var draftMinutes: Int?

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
                .modifier(AdjustableLength(enabled: setsLength))
                // Bedside prints the countdown beside the dial; read it there, once.
                .accessibilityHidden(!showsCountdown)
        }
        // Tick leans on the rim in the square's empty corner, so the layout
        // around the dial is untouched. Too cramped on small dials. Its own
        // element, beside the dial's, so its crown can be used with VoiceOver.
        .overlay {
            if showsMascot, size >= DialTick.minimumDial {
                DialTick(stage: stage, celebration: celebration, crown: crown)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .position(x: size * 0.9, y: size * 0.88)
            }
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
                    .modifier(PausedTone(active: session?.isPaused == true))
                    // Spring the arc when the stage changes; between ticks it just steps.
                    .animation(Motion.wind(reduceMotion), value: stageKey)
                    // A new length winds the idle arc there, one detent at a time while dragging.
                    .animation(Motion.snappy(reduceMotion), value: idleMinutes)
            }
            .modifier(CelebrationPulse(trigger: celebration))

            if case .idle = stage {
                if size >= 220 {
                    DialNumbers(size: size)
                        .transition(.opacity)
                }
                IdleKnobGlow(size: size, fraction: Double(idleMinutes) / 60)
                    .animation(Motion.snappy(reduceMotion), value: idleMinutes)
                    .transition(.opacity)
                if teaches {
                    GhostThumb(size: size, minutes: idleMinutes)
                        .transition(.opacity)
                }
            }

            if case .focusComplete = stage {
                OvertimeArc(size: size)
            }

            // Only the knob takes the drag, so a swipe anywhere else on the
            // dial still scrolls the page (the dial fills it at large text sizes).
            if setsLength {
                let grab = DialLength.grabSize(side: size)
                Color.clear
                    .frame(width: grab, height: grab)
                    .contentShape(.circle)
                    .position(DialLength.knobPoint(minutes: idleMinutes, side: size))
                    .gesture(lengthDrag)
                    .sensoryFeedback(.selection, trigger: draftMinutes)
            }

            center(session: session)
                .padding(size * 0.25)
        }
        .frame(width: size, height: size)
        .coordinateSpace(.named(Self.dialSpace))
    }

    private static let dialSpace = "dial"

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
                    // A constant value never bounces: still with Reduce Motion.
                    .symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: reduceMotion ? 0 : celebration)
                    .transition(.pop(reduceMotion))
                OvertimeLabel(size: size)
            } else {
                TimelineView(TickSchedule(countdownEnd: session?.endDate)) { context in
                    let clock = TimeFormat.clock(session?.remaining(at: context.date) ?? idleFocus)
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

    /// The dial sets the next session's length only while waiting to start,
    /// and not in bedside mode.
    private var setsLength: Bool {
        guard case .idle = stage else { return false }
        return showsCountdown
    }

    /// The length the idle dial shows: under the finger, or the saved one.
    private var idleMinutes: Int { draftMinutes ?? services.settings.length.minutes }

    /// What the idle countdown reads. Test timers show their seconds until
    /// the knob is dragged.
    private var idleFocus: TimeInterval {
        draftMinutes.map { TimeInterval($0 * 60) } ?? services.plan.focus
    }

    private var lengthDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.dialSpace))
            .onChanged { drag in
                dialHintSeen = true
                let center = CGPoint(x: size / 2, y: size / 2)
                let angle = DialLength.angle(of: drag.location, around: center)
                // The drag starts on the knob, so it starts from the current
                // length: grabbing it at 60 can't read as just past 12.
                draftMinutes = DialLength.minutes(atAngle: angle, previous: idleMinutes)
            }
            .onEnded { _ in
                if let draftMinutes {
                    services.settings.length = SessionLength(minutes: draftMinutes)
                }
                draftMinutes = nil
            }
    }

    private func arcValue(session: ActiveSession?, now: Date) -> Double {
        switch stage {
        case .idle: DialLength.arcValue(remaining: TimeInterval(idleMinutes * 60))
        case .active(let s): DialLength.arcValue(remaining: s.remaining(at: now))
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
            return String(localized: "Ready, \(TimeFormat.spokenDuration(idleFocus))")
        case .active(let s):
            let left = TimeFormat.spokenTimeLeft(s.remaining(at: date))
            return s.isPaused ? String(localized: "Paused, \(left)") : left
        case .focusComplete:
            let minutes = services.engine.overtime(at: date).map { Int($0 / 60) } ?? 0
            return minutes > 0 ? Copy.overtimeSpoken(minutes: minutes) : ""
        }
    }
}

// MARK: - Tick

/// Tick for the dial: the state `TickDirector` picks for where the session
/// stands (and the alarm), with its ring following the timer. It changes
/// on its own a minute past the bell, at night, when dozing off, and for
/// a set of four's streak after done. A focus session is a workout.
/// Cancel one and Tick shrugs it off for a moment.
private struct DialTick: View {
    /// Below this the dial has no room to spare in its corner.
    static let minimumDial: CGFloat = 200

    let stage: SessionStage
    let celebration: Int
    let crown: (label: String, action: () -> Void)?
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    /// When Tick was last on screen, for hello after a week away.
    @AppStorage(Onboarding.tickLastSeenKey) private var lastSeen: Double = 0
    @State private var stageSince = Date.now
    @State private var helloUntil: Date?
    @State private var interruptedUntil: Date?
    /// The state on show, which settles 0.3 s after a burst of changes.
    @State private var shown: TickPose?
    @State private var lastShown: Date?
    /// The time Tick is drawn for, moved on by the schedule below.
    @State private var clock = Date.now

    var body: some View {
        let schedule = TickSchedule(countdownEnd: stage.runningEnd, interval: ringStep,
                                    wakeDates: wakeDates(after: .now))
        tick(at: clock)
            // The schedule only moves the clock on, so Tick itself is never
            // rebuilt when the schedule changes: its springs carry on.
            .background {
                TimelineView(schedule) { context in
                    Color.clear.onChange(of: context.date, initial: true) { _, date in clock = date }
                }
                .id(schedule)
            }
        .onChange(of: StageKey(stage)) { old, new in
            stageSince = .now
            clock = .now
            // Straight from focusing to nothing is a cancel (finishing goes to complete).
            if old.kind == 1, old.phase == .focus, new.kind == 0 {
                interruptedUntil = .now.addingTimeInterval(TickDirector.interruptedLength)
            }
        }
        .onAppear(perform: greet)
        .onDisappear { lastSeen = Date.now.timeIntervalSince1970 }
    }

    private func tick(at date: Date) -> some View {
        let pose = director(at: date).pose(at: date)
        let dismiss: (() -> Void)? = services.alarmRinging ? { services.stopAlarm() } : nil
        return TickView(pose: shown ?? pose, progress: .fixed(TickPose.ringProgress(for: stage, at: date)),
                        celebration: celebration, crown: crown, onDismiss: dismiss, workout: workout)
            .onChange(of: pose, initial: true) { show(pose) }
    }

    private func director(at date: Date) -> TickDirector {
        TickDirector(stage: stage, alarmRinging: services.alarmRinging, overtime: engine.overtime(at: date),
                     hour: services.calendar.component(.hour, from: date), stageSince: stageSince,
                     helloUntil: helloUntil, interruptedUntil: interruptedUntil)
    }

    /// The focus session as a workout: running or paused, or just finished.
    private var workout: TickWorkout? {
        switch stage {
        case .active(let session) where session.phase == .focus: TickWorkout(session: session)
        case .focusComplete(let focus): TickWorkout(finished: focus)
        default: nil
        }
    }

    /// Shows a change at once, unless one showed under 0.3 s ago; then the
    /// latest shows when that's up.
    private func show(_ pose: TickPose) {
        let now = Date.now
        let at = TickDirector.showTime(for: now, lastShown: lastShown)
        guard at > now else {
            shown = pose
            lastShown = now
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(at.timeIntervalSince(now)))
            let latest = director(at: .now).pose(at: .now)
            shown = latest
            lastShown = .now
        }
    }

    /// Hello on first launch or after a week away.
    private func greet() {
        let now = Date.now
        if TickDirector.greets(lastSeen: lastSeen == 0 ? nil : Date(timeIntervalSince1970: lastSeen), now: now) {
            helloUntil = now.addingTimeInterval(TickDirector.helloLength)
        }
        lastSeen = now.timeIntervalSince1970
    }

    /// Seconds between ring steps: each moves the arc under half a point
    /// on Tick's 100-point ring, so it looks smooth at very little cost.
    private var ringStep: TimeInterval {
        guard case .active(let session) = stage else { return 60 }
        return max(1, session.plannedDuration * 0.5 / 170)
    }

    /// A minute past the bell, night starting or ending while idle, and the
    /// director's own changes (hello ending, dozing off, the streak).
    private func wakeDates(after date: Date) -> [Date] {
        var dates: [Date]
        switch stage {
        case .idle:
            let calendar = services.calendar
            dates = [22, 6].compactMap {
                calendar.nextDate(after: date, matching: DateComponents(hour: $0, minute: 0), matchingPolicy: .nextTime)
            }
        case .focusComplete:
            dates = engine.overtimeChanges(after: date).prefix(1).map { $0 }
        case .active:
            dates = []
        }
        if let change = director(at: date).nextChange(after: date) { dates.append(change) }
        return dates
    }
}

/// Which stage it is, not where in it: changes when a session starts,
/// switches phase, or finishes, not on every pause.
private struct StageKey: Equatable {
    let kind: Int
    let id: UUID?
    let phase: SessionPhase?

    init(_ stage: SessionStage) {
        switch stage {
        case .idle: (kind, id, phase) = (0, nil, nil)
        case .active(let session): (kind, id, phase) = (1, session.id, session.phase)
        case .focusComplete(let focus): (kind, id, phase) = (2, focus.id, nil)
        }
    }
}

private extension SessionStage {
    /// The end of a running phase, for the ring's steps.
    var runningEnd: Date? {
        if case .active(let session) = self { return session.endDate }
        return nil
    }
}

// MARK: - Overtime

/// Whole minutes worked past the bell at `date`, while they can still be kept.
@MainActor
private func overtimeMinutes(_ engine: SessionEngine, at date: Date) -> Int? {
    engine.overtime(at: date).map { Int($0 / 60) }
}

/// After the bell the dial keeps time: a thin rust lap round the rim, one
/// tick per minute you kept going. Redraws once a minute.
private struct OvertimeArc: View {
    let size: CGFloat
    @Environment(SessionEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let schedule = TickSchedule(wakeDates: engine.overtimeChanges(after: .now))
        TimelineView(schedule) { context in
            let minutes = overtimeMinutes(engine, at: context.date) ?? 0
            Circle()
                .trim(from: 0, to: Double(minutes) / 60)
                .stroke(Retro.rust, style: StrokeStyle(lineWidth: size * 0.014, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.985, height: size * 0.985)
                .opacity(minutes > 0 ? 1 : 0)
                .animation(Motion.snappy(reduceMotion), value: minutes)
        }
        .id(schedule)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// "+3 min" under the seal while there's time past the bell to keep.
private struct OvertimeLabel: View {
    let size: CGFloat
    @Environment(SessionEngine.self) private var engine

    var body: some View {
        let schedule = TickSchedule(wakeDates: engine.overtimeChanges(after: .now))
        TimelineView(schedule) { context in
            if let minutes = overtimeMinutes(engine, at: context.date), minutes > 0 {
                Text(Copy.overtimeShort(minutes: minutes))
                    .font(.retroDisplay(size: size * 0.06))
                    .foregroundStyle(Retro.rustText)
                    .retroNumber()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .id(schedule)
    }
}

/// Under the completion summary: offers the minutes worked past the bell
/// as focus, then says they were kept.
struct OvertimeChip: View {
    let focus: CompletedFocus
    @Environment(SessionEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let schedule = TickSchedule(wakeDates: engine.overtimeChanges(after: .now))
        TimelineView(schedule) { context in
            Group {
                if let minutes = overtimeMinutes(engine, at: context.date), minutes > 0 {
                    Button(action: engine.keepOvertime) {
                        Label(Copy.keepOvertime(minutes: minutes), systemImage: "plus.circle.fill")
                            .font(.retro(.meta).weight(.semibold))
                            .foregroundStyle(Retro.rustText)
                            .retroChip()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Copy.keepOvertimeSpoken(minutes: minutes))
                    .accessibilityInputLabels([Copy.keepOvertime(minutes: minutes)])
                    .transition(.pop(reduceMotion))
                } else if let kept = focus.keptOvertime {
                    Label(Copy.keptOvertime(minutes: Int(kept / 60)), systemImage: "checkmark.circle")
                        .font(.retro(.meta))
                        .foregroundStyle(Retro.inkSoft)
                        .frame(minHeight: 36)
                        .transition(.opacity)
                }
            }
            .animation(Motion.calm(reduceMotion), value: focus.keptOvertime)
        }
        .id(schedule)
    }
}

/// A slow "breathing" halo on the knob when the timer starts waiting: three
/// breaths, then it rests, so an idle screen draws nothing. It follows the
/// knob round the dial as the length changes.
private struct IdleKnobGlow: View {
    let size: CGFloat
    /// Where the knob is, 0...1 clockwise from 12 o'clock.
    let fraction: Double

    var body: some View {
        let line = size * 0.075
        Circle()
            .fill(Retro.orange)
            .frame(width: line * 2.4, height: line * 2.4)
            .blur(radius: line * 0.55)
            .offset(y: -size / 2 * RetroDial.arcRadiusRatio(showsTicks: true))
            .frame(width: size, height: size)
            .rotationEffect(.radians(fraction * 2 * .pi))
            .modifier(BreatheThrice(low: 0.08, high: 0.38, resting: 0.2))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// First launch: a faint thumb on the knob shows the dial turns, sweeping
/// five minutes on and back three times, then resting there. Still with
/// Reduce Motion. It never takes a touch.
private struct GhostThumb: View {
    let size: CGFloat
    let minutes: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppServices.self) private var services
    @State private var play = false

    var body: some View {
        let still = reduceMotion || services.power.isConstrained
        thumb(sweep: 0)
            .opacity(0)
            .overlay {
                if still {
                    thumb(sweep: 0)
                } else {
                    Color.clear.keyframeAnimator(initialValue: 0.0, trigger: play) { _, sweep in
                        thumb(sweep: sweep)
                    } keyframes: { [speed = Motion.speed] _ in
                        LinearKeyframe(0, duration: 0.8 * speed)
                        CubicKeyframe(1, duration: 0.9 * speed)
                        CubicKeyframe(1, duration: 0.25 * speed)
                        CubicKeyframe(0, duration: 0.9 * speed)
                        CubicKeyframe(0, duration: 0.5 * speed)
                        CubicKeyframe(1, duration: 0.9 * speed)
                        CubicKeyframe(1, duration: 0.25 * speed)
                        CubicKeyframe(0, duration: 0.9 * speed)
                        CubicKeyframe(0, duration: 0.5 * speed)
                        CubicKeyframe(1, duration: 0.9 * speed)
                        CubicKeyframe(1, duration: 0.25 * speed)
                        CubicKeyframe(0, duration: 0.9 * speed)
                        CubicKeyframe(0, duration: 0.5 * speed)
                    }
                    .onAppear { play.toggle() }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The fingertip on the knob, `sweep` of five minutes further round.
    private nonisolated func thumb(sweep: Double) -> some View {
        let angle = (Double(minutes) + 5 * sweep) / 60 * 2 * .pi
        let radius = size / 2 * RetroDial.arcRadiusRatio(showsTicks: true)
        let glyph = size * 0.13
        return Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: glyph))
            .foregroundStyle(Retro.ink.opacity(0.45))
            // The fingertip is the glyph's top-left corner.
            .offset(x: glyph * 0.42, y: glyph * 0.5)
            .offset(x: radius * sin(angle), y: -radius * cos(angle))
            .frame(width: size, height: size)
    }
}

/// After the very first session: says that's all there is to it.
struct WelcomeLine: View {
    var body: some View {
        VStack(spacing: Space.xxs) {
            Text(Copy.wholeApp)
                .retroFont(.headline)
                .foregroundStyle(Retro.ink)
            Text(Copy.wholeAppDetail)
                .font(.retro(.meta))
                .foregroundStyle(Retro.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A paused dial goes still and warm, like an old photograph: less colour,
/// with a mustard cast over the ring.
private struct PausedTone: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .saturation(active ? 0.35 : 1)
            .colorMultiply(active ? Color(red: 1, green: 0.9, blue: 0.72) : .white)
    }
}

/// The kitchen-timer minutes round the idle dial, between the arc and the
/// ticks. They go when the session starts.
private struct DialNumbers: View {
    let size: CGFloat

    var body: some View {
        let radius = size / 2 * 0.78
        ZStack {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                let angle = DialLength.angle(forMinutes: minutes)
                Text(minutes, format: .number)
                    .font(.retroDisplay(size: size * 0.032))
                    .foregroundStyle(Retro.inkSoft)
                    .offset(x: radius * sin(angle), y: -radius * cos(angle))
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Swipe up or down with VoiceOver to change the waiting dial by five minutes.
private struct AdjustableLength: ViewModifier {
    let enabled: Bool
    @Environment(AppServices.self) private var services

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAdjustableAction { direction in
                let minutes = services.settings.length.minutes
                switch direction {
                case .increment: services.settings.length = SessionLength(minutes: minutes + SessionLength.minuteStep)
                case .decrement: services.settings.length = SessionLength(minutes: minutes - SessionLength.minuteStep)
                @unknown default: break
                }
            }
        } else {
            content
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Redraws only when "+5 min" appears or goes away.
        let schedule = TickSchedule(wakeDates: engine.controlChanges(after: .now))
        TimelineView(schedule) { context in
            let canExtend = engine.canExtend(at: context.date)
            HStack(spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Image(systemName: session.phase == .focus ? "book.closed.fill" : "cup.and.saucer.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Retro.tint(for: session.phase))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    Text(session.phase == .focus ? Copy.displayName(session.name) : Copy.breakAfter(session.name))
                        .retroFont(.headline)
                        .foregroundStyle(Retro.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
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
                    .transition(.pop(reduceMotion))
                }
            }
            .padding(.leading, Space.l)
            .padding(.trailing, canExtend ? Space.m : Space.l)
            .padding(.vertical, canExtend ? Space.xxs : Space.s)
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
            HStack(spacing: Space.xxs) {
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
                    .accessibilityShowsLargeContentViewer { Label("Dismiss", systemImage: "xmark") }
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
        case .alarmsOff: String(localized: "Alarms are off, so Clockin can only notify you. Turn on")
        case .unknown, .ready: nil
        }
    }

    private var settings: URL? {
        switch status {
        case .notificationsOff: URL(string: UIApplication.openNotificationSettingsURLString)
        case .liveActivitiesOff, .alarmsOff: URL(string: UIApplication.openSettingsURLString)
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
        HStack(spacing: Space.xs) {
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

// MARK: - Length chips

/// The three lengths under the dial while waiting to start: the same
/// choice as Settings › Timer, one tap away. A length dragged on the dial
/// shows as a fourth chip. The dial winds to the new length.
struct LengthChips: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts taps, for the haptic; the dial ticks for itself while dragged.
    @State private var taps = 0

    var body: some View {
        let length = services.settings.length
        var lengths = Preset.allCases.map(SessionLength.preset)
        if case .custom = length { lengths.append(length) }
        return GlassEffectContainer(spacing: Space.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Space.xs) { chips(lengths) }
            } else {
                // One row, or two when a narrow phone can't fit four.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.xs) { chips(lengths) }
                    Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                        GridRow { chips(Array(lengths.prefix(2))) }
                        GridRow { chips(Array(lengths.dropFirst(2))) }
                    }
                }
            }
        }
        .animation(Motion.snappy(reduceMotion), value: length)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Session length"))
    }

    /// A button per preset; a dragged length is shown, already chosen.
    private func chips(_ lengths: [SessionLength]) -> some View {
        ForEach(lengths, id: \.self) { length in
            let selected = length == services.settings.length
            switch length {
            case .preset:
                Button {
                    services.settings.length = length
                    taps += 1
                } label: {
                    chip(length, selected: selected)
                }
                .buttonStyle(.plain)
            case .custom:
                chip(length, selected: selected)
                    .transition(.pop(reduceMotion))
            }
        }
    }

    private func chip(_ length: SessionLength, selected: Bool) -> some View {
        Text(length.chipTitle)
            .font(.retro(.meta))
            .fontWeight(selected ? .bold : .medium)
            .foregroundStyle(selected ? Retro.ink : Retro.inkSoft)
            .lineLimit(1)
            .retroChip(selected: selected)
            .accessibilityLabel(length.spokenSummary)
            .accessibilityAddTraits(selected ? .isSelected : [])
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
                HStack(spacing: Space.xs) {
                    ForEach(names, id: \.self) { name in
                        Button { pick(name) } label: {
                            Text(name)
                                .font(.retro(.meta))
                                .foregroundStyle(Retro.ink)
                                .lineLimit(1)
                                .retroChip()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(String(localized: "Uses this name"))
                    }
                }
                .padding(Space.xxs)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(focus: CompletedFocus, day: Date) {
        self.focus = focus
        self.day = day
        _today = Query(filter: FocusRecord.completed(on: day))
    }

    var body: some View {
        let total = TodayStats.rows(saved: today.map(\.row), pending: engine.pendingRecords(on: day)).totalSeconds
        // Three across, or a column when large text wouldn't fit them.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Space.s)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            stat(TimeFormat.duration(focus.focusSeconds), "Focused", index: 0)
            if !stacked { divider }
            stat(Copy.displayName(focus.name), "Session", index: 1)
            if !stacked { divider }
            stat(TimeFormat.duration(total), "Today", index: 2)
        }
        .padding(.vertical, Space.s)
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
        VStack(spacing: Space.xxs) {
            Text(value)
                .retroFont(.headline)
                .foregroundStyle(Retro.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            Text(caption).retroLabel()
        }
        // Clear of the dividers, so a long name shrinks before it touches them.
        .padding(.horizontal, Space.xs)
        .frame(maxWidth: .infinity)
        .transition(.rise(reduceMotion, delay: Motion.stagger(index, after: Motion.afterCelebration, reduceMotion)))
    }

}
