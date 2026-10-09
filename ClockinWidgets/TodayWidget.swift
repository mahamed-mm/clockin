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
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        var dates = [now]
        // Refresh when the running phase ends so the count updates without the app.
        if let end = loadState().active?.endDate, end > now { dates.append(end) }
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        dates.append(midnight)
        completion(Timeline(entries: dates.map(entry(at:)), policy: .after(midnight)))
    }

    private func loadState() -> PersistedSessionState {
        DefaultsSessionStateStore().load()
    }

    private func entry(at date: Date) -> TodayEntry {
        let active = loadState().active
        var rows: [(id: UUID, completedAt: Date, seconds: TimeInterval)] = []
        if let container = try? SharedStore.makeModelContainer() {
            let context = ModelContext(container)
            rows = TodayStats.fetchRecords(on: date, calendar: .current, context: context)
                .map { ($0.id, $0.completedAt, $0.focusSeconds) }
        }
        let stats = TodayStats.make(records: rows, unrecordedActive: active, now: date)
        let stillRunning = active.flatMap { $0.isFinished(at: date) ? nil : $0 }
        return TodayEntry(date: date, stats: stats, active: stillRunning)
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
                Text(active.phase == .focus ? active.name : "Break")
                    .retroLabel()
                    .lineLimit(1)
            }
        } else {
            VStack(spacing: 4) {
                ZStack {
                    RetroDial(value: min(1, Double(entry.stats.sessionCount) / 4),
                              tint: Retro.orange, lineWidthRatio: 0.09)
                    VStack(spacing: 0) {
                        Text("\(entry.stats.focusMinutes)")
                            .font(.retroDisplay(size: 30))
                            .foregroundStyle(Retro.ink)
                            .minimumScaleFactor(0.6)
                        Text("min").font(.retro(.label)).foregroundStyle(Retro.inkSoft)
                    }
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
                Image(systemName: entry.active?.phase == .rest ? "cup.and.saucer.fill" : "timer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Retro.ink)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's focus").retroLabel()
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
            Text("\(entry.stats.focusMinutes)")
                .font(.retroDisplay(size: 40))
                .tracking(-1)
                .foregroundStyle(Retro.ink)
                .minimumScaleFactor(0.6)
            Text("min")
                .font(.retro(.headline))
                .foregroundStyle(Retro.inkSoft)
        }
    }

    private var miniDial: some View {
        // Same reading as the app: time left while running, otherwise today's sessions out of four.
        let value = entry.active.map { $0.plannedDuration > 0 ? $0.remaining(at: entry.date) / $0.plannedDuration : 0 }
            ?? min(1, Double(entry.stats.sessionCount) / 4)
        return RetroDial(value: value,
                         tint: Retro.tint(for: entry.active?.phase ?? .focus),
                         showsTicks: family != .systemSmall,
                         showsKnob: family != .systemSmall,
                         lineWidthRatio: family == .systemSmall ? 0.16 : 0.09)
    }

    @ViewBuilder
    private func activeLine(_ active: ActiveSession) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Retro.tint(for: active.phase)).frame(width: 6, height: 6)
            Text(active.phase == .focus ? active.name : "Break")
                .lineLimit(1)
            Spacer(minLength: 2)
            if let end = active.endDate {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56, alignment: .trailing)
            } else {
                Text("Paused")
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
