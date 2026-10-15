import SwiftData
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let stats: TodayStats
    let active: ActiveSession?
    /// The running session name's symbol.
    var symbol = SymbolCatalog.unnamed
    /// What the big button would do at this moment, for the widget's own.
    var face = ControlFace.start
    /// For the large widget: the week so far, and today's sessions, newest first.
    var week: [DayTotal] = []
    var sessions: [WidgetSnapshot.Session] = []
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, stats: TodayStats(focusSeconds: 50 * 60, sessionCount: 2), active: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(at: [.now])[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let state = DefaultsSessionStateStore().load()
        let dates = WidgetSnapshot.timelineDates(at: now, active: state.active)
        completion(Timeline(entries: entries(at: dates, state: state), policy: .after(dates.last ?? now)))
    }

    private func entries(at dates: [Date], state: PersistedSessionState = DefaultsSessionStateStore().load())
        -> [TodayEntry] {
        let snapshot = WidgetSnapshotStore().load() ?? fallbackSnapshot(state: state)
        let active = state.active
        let book = DefaultsSymbolBookStore().load()
        let symbol = book.symbol(for: active?.name ?? "")
        return dates.map { date in
            let stillRunning = active.flatMap { $0.isFinished(at: date) ? nil : $0 }
            let sessions = snapshot.sessions(on: date).map { session in
                var session = session
                session.symbol = session.symbol ?? book.symbol(for: session.name ?? "")
                return session
            }
            return TodayEntry(date: date, stats: snapshot.stats(at: date, active: active), active: stillRunning,
                              symbol: symbol, face: ControlFace(state: state, now: date),
                              week: snapshot.week(at: date, active: active), sessions: sessions)
        }
    }

    /// Until the app writes a snapshot (the first run after an update), read
    /// the store directly. Read-only, so the widget can never migrate it.
    private func fallbackSnapshot(state: PersistedSessionState) -> WidgetSnapshot {
        let now = Date.now
        var saved: [WidgetSnapshot.Session] = []
        if let container = try? SharedStore.makeModelContainer(readOnly: true) {
            saved = TodayStats.fetchRecords(on: now, calendar: .autoupdatingCurrent, context: ModelContext(container))
                .map {
                    WidgetSnapshot.Session(id: $0.id, completedAt: $0.completedAt, seconds: $0.focusSeconds,
                                           countsAsFull: $0.row.countsAsFull, name: $0.name, startedAt: $0.startedAt)
                }
        }
        let ids = Set(saved.map(\.id))
        let waiting = (state.pendingRecords ?? []).filter { !ids.contains($0.id) }.map {
            WidgetSnapshot.Session(id: $0.id, completedAt: $0.completedAt, seconds: $0.focusSeconds,
                                   countsAsFull: $0.countsAsFull, name: $0.name, startedAt: $0.startedAt)
        }
        // Today only: the week strip shows today alone until the app writes one.
        return WidgetSnapshot(sessions: saved + waiting, week: nil, writtenAt: now)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { PaperBackground() }
                .widgetURL(URL(string: "clockin://focus"))
        }
        .configurationDisplayName("Today's Focus")
        .description("Minutes of focus you've finished today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// False in StandBy, where the system removes the paper background.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: TodayEntry

    var body: some View {
        if !showsBackground && family == .systemSmall {
            standBy
        } else {
            switch family {
            case .systemMedium: medium
            case .systemLarge: LargeTodayView(entry: entry)
            default: small
            }
        }
    }

    // MARK: StandBy

    /// Bedside layout: a live dial with the countdown inside while a session
    /// runs, otherwise today's minutes on the dial.
    @ViewBuilder
    private var standBy: some View {
        if let active = entry.active {
            let reading = TimerReading(session: active, at: entry.date)
            VStack(spacing: 4) {
                LiveDial(reading: reading, phase: active.phase, lineWidthRatio: 0.09) {
                    FocusCountdown(reading: reading)
                        .font(.retroDisplay(size: 24))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Retro.ink)
                        .padding(.horizontal, 30)
                }
                Text(active.breakLabel ?? Copy.displayName(active.name))
                    .retroLabel()
                    .lineLimit(1)
            }
        } else {
            VStack(spacing: 4) {
                ZStack {
                    RetroDial(value: min(1, Double(entry.stats.sessionCount) / Double(SessionPills.setSize)),
                              tint: Retro.orange, lineWidthRatio: 0.09)
                    DurationText(seconds: entry.stats.focusSeconds, size: 30, stacks: true,
                                 spoken: Copy.spokenFocusedToday(seconds: entry.stats.focusSeconds))
                        .padding(.horizontal, 16)
                }
                SessionPills(completed: entry.stats.sessionCount,
                             pillWidth: 16, pillHeight: 5, spacing: 3)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("Today").retroLabel()
                Spacer()
                FocusWidgetButton(entry: entry, compact: true)
            }
            Spacer(minLength: 0)
            minutes
            if let active = entry.active {
                activeLine(active)
            }
            SessionPills(completed: entry.stats.sessionCount,
                         inProgress: entry.active?.phase == .focus,
                         pillWidth: 22, pillHeight: 6)
                .padding(.top, 4)
        }
    }

    private var medium: some View {
        HStack(spacing: 18) {
            ZStack {
                miniDial
                // Its ring shows the time left as of this entry.
                TickBadge(pose: TickPose.forWidget(entry.active, at: entry.date,
                                                   hour: TickPose.hour(at: entry.date, calendar: .autoupdatingCurrent)),
                          progress: TickPose.ringProgress(for: entry.active.map(SessionStage.active) ?? .idle,
                                                          at: entry.date))
                    .frame(width: 50, height: 50)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's Focus").retroLabel()
                minutes
                if let active = entry.active {
                    activeLine(active)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    SessionPills(completed: entry.stats.sessionCount,
                                 inProgress: entry.active?.phase == .focus,
                                 pillWidth: 22, pillHeight: 6)
                    Spacer(minLength: 4)
                    FocusWidgetButton(entry: entry, compact: false)
                }
            }
        }
    }

    /// Today's total as the app says it, "1 h 15 min".
    private var minutes: some View {
        DurationText(seconds: entry.stats.focusSeconds, size: 40,
                     spoken: Copy.spokenFocusedToday(seconds: entry.stats.focusSeconds))
    }

    /// Same reading as the app: time left, draining on its own between
    /// timeline entries while a session runs; otherwise today's sessions out of a set.
    @ViewBuilder
    private var miniDial: some View {
        let small = family == .systemSmall
        if let active = entry.active {
            LiveDial(reading: TimerReading(session: active, at: entry.date), phase: active.phase,
                     lineWidthRatio: small ? 0.16 : 0.09, showsTicks: !small) { EmptyView() }
        } else {
            RetroDial(value: min(1, Double(entry.stats.sessionCount) / Double(SessionPills.setSize)),
                      tint: Retro.orange, showsTicks: !small, showsKnob: !small,
                      lineWidthRatio: small ? 0.16 : 0.09)
        }
    }

    private func activeLine(_ active: ActiveSession) -> some View {
        ActiveLine(entry: entry, active: active)
    }

}

#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry.preview(seconds: 75 * 60, sessions: 3)
    TodayEntry.preview(active: TodayEntry.running(), face: .pause)
    TodayEntry.preview(active: TodayEntry.running(paused: true), face: .resume)
    TodayEntry.preview(sessions: 3, face: .startBreak)
    TodayEntry.preview(active: TodayEntry.running(.rest), face: .pause)
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry.preview(seconds: 50 * 60, sessions: 2)
    TodayEntry.preview(active: TodayEntry.running(), face: .pause)
    TodayEntry.preview(active: TodayEntry.running(paused: true), face: .resume)
    TodayEntry.preview(sessions: 3, face: .startBreak)
}

/// The running session in one line: phase, symbol, name and time left.
struct ActiveLine: View {
    let entry: TodayEntry
    let active: ActiveSession

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Retro.tint(for: active.phase)).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            if active.phase == .focus {
                Image(systemName: entry.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Retro.inkSoft)
                    .accessibilityHidden(true)
            }
            Text(active.breakLabel ?? Copy.displayName(active.name))
                .lineLimit(1)
            Spacer(minLength: 2)
            if let end = active.endDate {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56, alignment: .trailing)
            } else {
                Text(Copy.paused)
            }
        }
        .font(.retro(.meta))
        .foregroundStyle(Retro.ink)
    }
}

/// The big button's twin: Start, Pause, Resume or Start break, as the app's
/// would at this moment. It runs in the app, silently, and the widgets redraw
/// after. A tap anywhere else still opens the app.
struct FocusWidgetButton: View {
    let entry: TodayEntry
    /// Just the symbol, in a circle, where there's no room for the title.
    let compact: Bool

    private var tint: Color {
        entry.active?.phase == .rest || entry.face.action == .startBreak ? Retro.avocado : Retro.orange
    }

    var body: some View {
        if compact {
            round
        } else {
            // The title when it fits, else just the symbol: never "Star…".
            ViewThatFits(in: .horizontal) {
                button {
                    Label(entry.face.title, systemImage: entry.face.symbol)
                        .fixedSize()
                        .frame(minHeight: 30)
                }
                .buttonBorderShape(.capsule)
                round
            }
        }
    }

    private var round: some View {
        button {
            Label(entry.face.title, systemImage: entry.face.symbol)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
    }

    private func button(@ViewBuilder label: () -> some View) -> some View {
        Button(intent: FocusButtonIntent(), label: label)
            .font(.retro(.meta).weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .widgetAccentable()
    }
}
