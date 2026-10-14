import SwiftUI
import WidgetKit

/// Clockin on the Lock Screen: Tick in a ring, today's focus, or the
/// session running. Session names are hidden while the phone is locked if
/// the user asks for that.
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreenWidget", provider: TodayProvider()) { entry in
            LockScreenView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "clockin://focus"))
        }
        .configurationDisplayName("Clockin")
        .description(String(localized: "Today's focus, or the session running."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var line: LockScreenLine {
        LockScreenLine(stats: entry.stats, active: entry.active, symbol: entry.symbol, at: entry.date)
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: inline
        }
    }

    // MARK: Circular

    private var circular: some View {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: entry.date)
        return ZStack {
            AccessoryWidgetBackground()
            Group {
                if let active = entry.active {
                    TickLiveGlyph(pose: line.pose(hour: hour), reading: TimerReading(session: active, at: entry.date),
                                  phase: active.phase, crown: false)
                } else {
                    TickLiveGlyph(pose: line.pose(hour: hour),
                                  progress: Double(entry.stats.sessionCount) / Double(TimerPlan.sessionsPerSet),
                                  crown: false)
                }
            }
            .padding(3)
            .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Rectangular

    @ViewBuilder
    private var rectangular: some View {
        switch line {
        case .today(let seconds, let sessions):
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.focusedToday(seconds: seconds))
                    .font(.retro(.body))
                    .widgetAccentable()
                SessionPills(completed: sessions, pillWidth: 18, pillHeight: 5)
                Text(SessionPills.caption(completed: sessions))
                    .font(.retro(.meta))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        case .running(let name, let symbol, _, let end):
            session(name: name, symbol: symbol) {
                Text(timerInterval: entry.date...max(entry.date, end), countsDown: true)
                    .font(.retro(.title))
                    .monospacedDigit()
            }
        case .paused(let name, let symbol, _):
            session(name: name, symbol: symbol) {
                Text(Copy.paused)
                    .font(.retro(.body))
            }
        }
    }

    private func session(name: String, symbol: String, @ViewBuilder time: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(name)
                    .font(.retro(.body))
                    .lineLimit(1)
                    .privacySensitive()
            }
            time()
                .widgetAccentable()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Inline

    @ViewBuilder
    private var inline: some View {
        switch line {
        case .today(let seconds, _):
            Label(Copy.focusedToday(seconds: seconds), systemImage: "timer")
        case .running(let name, let symbol, _, let end):
            Label {
                Text("\(name) · \(Text(timerInterval: entry.date...max(entry.date, end), countsDown: true)) left")
            } icon: {
                Image(systemName: symbol)
            }
            .privacySensitive()
        case .paused(let name, let symbol, _):
            Label(name + " · " + Copy.paused, systemImage: symbol)
                .privacySensitive()
        }
    }

    // MARK: VoiceOver

    private var spoken: String {
        switch line {
        case .today(let seconds, let sessions):
            Copy.focusedToday(seconds: seconds) + ", " + Copy.pillsSpoken(completed: sessions, setSize: TimerPlan.sessionsPerSet, inProgress: false)
        case .running(let name, _, _, let end):
            name + ", " + TimeFormat.spokenTimeLeft(end.timeIntervalSince(entry.date))
        case .paused(let name, _, _):
            name + ", " + Copy.paused
        }
    }
}

// MARK: Previews

extension TodayEntry {
    // Shared by every widget's previews.
    static func preview(seconds: TimeInterval = 69 * 60, sessions: Int = 2, active: ActiveSession? = nil,
                        symbol: String = "flask.fill", face: ControlFace = .start) -> TodayEntry {
        TodayEntry(date: .now, stats: TodayStats(focusSeconds: seconds, sessionCount: sessions), active: active,
                   symbol: symbol, face: face)
    }

    static func running(_ phase: SessionPhase = .focus, paused: Bool = false) -> ActiveSession {
        ActiveSession(id: UUID(), name: "Chemistry", phase: phase, plannedDuration: 25 * 60, focusStartedAt: .now,
                      state: paused ? .paused(remaining: 12 * 60) : .running(endDate: .now.addingTimeInterval(12.5 * 60)))
    }
}

#Preview("Circular", as: .accessoryCircular) {
    LockScreenWidget()
} timeline: {
    TodayEntry.preview()
    TodayEntry.preview(active: TodayEntry.running())
    TodayEntry.preview(active: TodayEntry.running(paused: true))
    TodayEntry.preview(active: TodayEntry.running(.rest))
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenWidget()
} timeline: {
    TodayEntry.preview()
    TodayEntry.preview(sessions: 5)
    TodayEntry.preview(active: TodayEntry.running())
    TodayEntry.preview(active: TodayEntry.running(paused: true))
    TodayEntry.preview(active: TodayEntry.running(.rest))
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenWidget()
} timeline: {
    TodayEntry.preview()
    TodayEntry.preview(active: TodayEntry.running())
    TodayEntry.preview(active: TodayEntry.running(paused: true))
}
