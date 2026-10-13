import SwiftData
import SwiftUI

/// Full-screen timer for a phone on the nightstand while Clockin is open:
/// the dial on the left, a bedside-clock countdown on the right, always in
/// the dark palette with softened numerals. Mirrors the StandBy Live
/// Activity, but works without charging; the screen stays on while it runs.
struct BedsideView: View {
    let session: ActiveSession
    private let day: Date
    private let leave: () -> Void
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var today: [FocusRecord]

    init(session: ActiveSession, day: Date, leave: @escaping () -> Void) {
        self.session = session
        self.day = day
        self.leave = leave
        _today = Query(filter: FocusRecord.completed(on: day))
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            HStack(spacing: height * 0.1) {
                DialFace(stage: .active(session), size: height * 0.84,
                         celebration: services.celebrations, showsCountdown: false, showsPills: false)
                    .frame(width: height * 0.84, height: height * 0.84)

                VStack(alignment: .leading, spacing: height * 0.03) {
                    HStack {
                        Text(session.isPaused ? Copy.paused : session.phase.label)
                            .retroLabel()
                        Spacer()
                        Button(action: leave) {
                            Image(systemName: "xmark")
                                .font(.system(size: height * 0.045, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Retro.inkSoft)
                        .accessibilityLabel(String(localized: "Leave bedside clock"))
                        .accessibilityShowsLargeContentViewer {
                            Label(String(localized: "Leave bedside clock"), systemImage: "xmark")
                        }
                    }
                    Text(session.phase == .focus ? Copy.displayName(session.name) : Copy.breakAfter(session.name))
                        .font(.retroFixed(.title, size: height * 0.09))
                        .foregroundStyle(Retro.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    TimelineView(TickSchedule(countdownEnd: session.endDate)) { context in
                        let clock = TimeFormat.clock(session.remaining(at: context.date))
                        Text(clock)
                            .font(.retroDisplay(size: height * 0.3))
                            .tracking(-2)
                            // A little softer than full ink in a dark room.
                            .foregroundStyle(Retro.ink.opacity(0.85))
                            .retroNumber(countsDown: true)
                            .animation(services.power.isConstrained ? nil : Motion.snappy(reduceMotion), value: clock)
                            .modifier(BlinkWhilePaused(active: session.isPaused))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .accessibilityLabel(TimeFormat.spoken(session.remaining(at: context.date)))
                    }

                    HStack {
                        Text(endsLine)
                            .font(.retroRounded(size: height * 0.06))
                            .foregroundStyle(Retro.inkSoft)
                        Spacer(minLength: 8)
                        Button(action: engine.togglePause) {
                            Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: height * 0.07, weight: .bold))
                                .frame(width: height * 0.17, height: height * 0.17)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(Retro.tint(for: session.phase))
                        .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
                        .accessibilityShowsLargeContentViewer {
                            Label(session.isPaused ? "Resume" : "Pause",
                                  systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        }
                    }

                    SessionPills(completed: TodayStats.rows(saved: today.map(\.row),
                                                            pending: engine.pendingRecords(on: day)).fullCount,
                                 inProgress: session.phase == .focus,
                                 pillWidth: height * 0.08, pillHeight: height * 0.022,
                                 spacing: height * 0.012,
                                 showsCaption: true, tint: Retro.tint(for: session.phase))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, height * 0.08)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PaperBackground(wash: Retro.tint(for: session.phase)))
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // Night palette whatever the phone's appearance; this view only.
        .environment(\.colorScheme, .dark)
        // VoiceOver's scrub gesture leaves, like the X.
        .accessibilityAction(.escape, leave)
    }

    private var endsLine: String {
        if session.isPaused { return "" }
        guard let end = session.endDate else { return "" }
        return session.phase == .focus ? Copy.ends(end) : Copy.breakUntil(end)
    }
}
