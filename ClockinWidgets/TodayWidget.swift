import SwiftData
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let stats: TodayStats
    let active: ActiveSession?
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
        let midnight = Calendar.autoupdatingCurrent.dayRange(containing: now).upperBound
        var dates = [now]
        // Refresh when the running phase ends so the count updates without the
        // app. An end after midnight waits for the timeline that starts then.
        if let end = state.active?.endDate, end > now, end < midnight { dates.append(end) }
        dates.append(midnight)
        completion(Timeline(entries: entries(at: dates, state: state), policy: .after(midnight)))
    }

    private func entries(at dates: [Date], state: PersistedSessionState = DefaultsSessionStateStore().load())
        -> [TodayEntry] {
        let snapshot = WidgetSnapshotStore().load() ?? fallbackSnapshot(state: state)
        let active = state.active
        return dates.map { date in
            let stillRunning = active.flatMap { $0.isFinished(at: date) ? nil : $0 }
            return TodayEntry(date: date, stats: snapshot.stats(at: date, active: active), active: stillRunning)
        }
    }

    /// Until the app writes a snapshot (the first run after an update), read
    /// the store directly. Read-only, so the widget can never migrate it.
    private func fallbackSnapshot(state: PersistedSessionState) -> WidgetSnapshot {
        let now = Date.now
        var saved: [FocusRow] = []
        if let container = try? SharedStore.makeModelContainer(readOnly: true) {
            saved = TodayStats.fetchRecords(on: now, calendar: .autoupdatingCurrent,
                                            context: ModelContext(container)).map(\.row)
        }
        return WidgetSnapshot(rows: TodayStats.rows(saved: saved, pending: state.pendingRecords ?? []), writtenAt: now)
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
        .supportedFamilies([.systemSmall, .systemMedium])
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
                Text(active.phase == .focus ? Copy.displayName(active.name) : Copy.rest)
                    .retroLabel()
                    .lineLimit(1)
            }
        } else {
            VStack(spacing: 4) {
                ZStack {
                    RetroDial(value: min(1, Double(entry.stats.sessionCount) / Double(SessionPills.setSize)),
                              tint: Retro.orange, lineWidthRatio: 0.09)
                    VStack(spacing: 0) {
                        Text(entry.stats.focusMinutes, format: .number)
                            .font(.retroDisplay(size: 30))
                            .foregroundStyle(Retro.ink)
                            .minimumScaleFactor(0.6)
                        Text("min").font(.retro(.label)).foregroundStyle(Retro.inkSoft)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(focusedToday)
                }
                SessionPills(completed: entry.stats.sessionCount,
                             pillWidth: 16, pillHeight: 5, spacing: 3)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").retroLabel()
                Spacer()
                miniDial.frame(width: 30, height: 30)
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
                                                   hour: Calendar.current.component(.hour, from: entry.date)),
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
                SessionPills(completed: entry.stats.sessionCount,
                             inProgress: entry.active?.phase == .focus,
                             pillWidth: 22, pillHeight: 6, showsCaption: true)
            }
        }
    }

    private var minutes: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(entry.stats.focusMinutes, format: .number)
                .font(.retroDisplay(size: 40))
                .tracking(-1)
                .foregroundStyle(Retro.ink)
                .minimumScaleFactor(0.6)
            Text("min")
                .retroFont(.headline)
                .foregroundStyle(Retro.inkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focusedToday)
    }

    /// "50 minutes of focus today", rather than "50", "min".
    private var focusedToday: String {
        String(localized: "\(TimeFormat.spokenDuration(TimeInterval(entry.stats.focusMinutes * 60))) of focus today")
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

    @ViewBuilder
    private func activeLine(_ active: ActiveSession) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Retro.tint(for: active.phase)).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(active.phase == .focus ? Copy.displayName(active.name) : Copy.rest)
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

#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, stats: TodayStats(focusSeconds: 75 * 60, sessionCount: 3), active: nil)
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, stats: TodayStats(focusSeconds: 50 * 60, sessionCount: 2), active: nil)
}
