import SwiftUI
import WidgetKit

/// The large widget: today up top with the button, the week's pills, then
/// today's sessions with their symbols, newest first.
struct LargeTodayView: View {
    let entry: TodayEntry
    /// Rows that fit under the header and strip.
    static let rows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            WidgetWeekStrip(totals: entry.week, today: entry.date)
            Rectangle().fill(Retro.ink.opacity(0.1)).frame(height: 1)
            list
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's Focus").retroLabel()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.stats.focusMinutes, format: .number)
                        .font(.retroDisplay(size: 40))
                        .tracking(-1)
                        .foregroundStyle(Retro.ink)
                    Text("min")
                        .retroFont(.headline)
                        .foregroundStyle(Retro.inkSoft)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.focusedToday(seconds: entry.stats.focusSeconds))
                SessionPills(completed: entry.stats.sessionCount, inProgress: entry.active?.phase == .focus,
                             pillWidth: 22, pillHeight: 6)
                // Under the pills rather than beside them, so it never runs into the button.
                Text(SessionPills.caption(completed: entry.stats.sessionCount))
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                TickBadge(pose: TickPose.forWidget(entry.active, at: entry.date,
                                                   hour: Calendar.current.component(.hour, from: entry.date)),
                          progress: TickPose.ringProgress(for: entry.active.map(SessionStage.active) ?? .idle,
                                                          at: entry.date))
                    .frame(width: 50, height: 50)
                FocusWidgetButton(entry: entry, compact: false)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let active = entry.active {
                ActiveLine(entry: entry, active: active)
            }
            if entry.sessions.isEmpty && entry.active == nil {
                Text("No sessions yet today")
                    .font(.retro(.body))
                    .foregroundStyle(Retro.inkSoft)
            }
            let shown = entry.sessions.prefix(entry.active == nil ? Self.rows : Self.rows - 1)
            ForEach(Array(shown), id: \.id) { session in
                row(session)
            }
            let more = entry.sessions.count - shown.count
            if more > 0 {
                Text(Copy.moreSessions(more))
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
            }
        }
    }

    private func row(_ session: WidgetSnapshot.Session) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(TimeFormat.time(session.completedAt))
                .font(.retro(.meta))
                .foregroundStyle(Retro.inkSoft)
                .frame(minWidth: 44, alignment: .leading)
            Image(systemName: session.symbol ?? SymbolCatalog.unnamed)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Retro.inkSoft)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(Copy.displayName(session.name ?? ""))
                .font(.retro(.body))
                .foregroundStyle(Retro.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(TimeFormat.duration(session.seconds))
                .font(.retro(.meta))
                .foregroundStyle(Retro.orangeText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.displayName(session.name ?? "") + ", " + TimeFormat.spokenDuration(session.seconds))
    }
}

/// The week as seven pill columns, still: the app's week strip without
/// its taps and animation.
struct WidgetWeekStrip: View {
    let totals: [DayTotal]
    let today: Date
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(totals, id: \.day) { entry in
                let isToday = calendar.isDate(entry.day, inSameDayAs: today)
                VStack(spacing: 4) {
                    Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.retro(.label))
                        .foregroundStyle(isToday ? Retro.ink : Retro.inkSoft)
                    SessionPills(completed: entry.sessions, pillWidth: 18, pillHeight: 5, axis: .vertical)
                        .opacity(entry.day > today && !isToday ? 0.4 : 1)
                    Circle()
                        .fill(Retro.orange)
                        .frame(width: 4, height: 4)
                        .opacity(isToday ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.daySpoken(entry, today: today, calendar: calendar))
            }
        }
    }
}

#Preview(as: .systemLarge) {
    TodayWidget()
} timeline: {
    TodayEntry.large()
    TodayEntry.large(active: TodayEntry.running(), face: .pause)
    TodayEntry.large(sessions: [])
}

extension TodayEntry {
    static func large(active: ActiveSession? = nil, face: ControlFace = .start,
                      sessions names: [String] = ["Spanish vocab", "Reading: Dune", "Chemistry", "Piano practice",
                                                  "Linear algebra", "Emails"]) -> TodayEntry {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let week = calendar.weekInterval(containing: now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }.map {
            DayTotal(day: $0, seconds: $0 > now ? 0 : 3_600, sessions: $0 > now ? 0 : 3)
        }
        let symbols = ["globe", "books.vertical.fill", "flask.fill", "music.note", "function", "envelope.fill"]
        let sessions = names.enumerated().map { index, name in
            WidgetSnapshot.Session(id: UUID(), completedAt: now.addingTimeInterval(Double(-index) * 2_100),
                                   seconds: 1_500, name: name, symbol: symbols[index % symbols.count])
        }
        return TodayEntry(date: now, stats: TodayStats(focusSeconds: Double(sessions.count) * 1_500,
                                                       sessionCount: sessions.count),
                          active: active, symbol: "flask.fill", face: face, week: days, sessions: sessions)
    }
}
