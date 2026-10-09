import SwiftData
import SwiftUI

/// Full-screen timer for a phone lying on its side while Clockin is open:
/// the dial on the left, a bedside-clock countdown on the right. Mirrors the
/// StandBy Live Activity, but works without charging and keeps the screen awake.
struct BedsideView: View {
    let session: ActiveSession
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var today: [FocusRecord]

    init(session: ActiveSession) {
        self.session = session
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        _today = Query(filter: #Predicate<FocusRecord> { $0.completedAt >= start && $0.completedAt < end })
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            HStack(spacing: height * 0.1) {
                DialFace(stage: .active(session), size: height * 0.84,
                         celebration: services.celebrations, showsCountdown: false, showsPills: false)
                    .frame(width: height * 0.84, height: height * 0.84)

                VStack(alignment: .leading, spacing: height * 0.03) {
                    Text(session.isPaused ? "Paused" : session.phase.label)
                        .retroLabel()
                    Text(session.phase == .focus ? session.name : "Break after \(session.name)")
                        .font(.system(size: height * 0.09, weight: .semibold, design: .serif))
                        .foregroundStyle(Retro.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let clock = TimeFormat.clock(session.remaining(at: context.date))
                        Text(clock)
                            .font(.retroDisplay(size: height * 0.3))
                            .tracking(-2)
                            .foregroundStyle(Retro.ink)
                            .retroNumber(countsDown: true)
                            .animation(Motion.snappy(reduceMotion), value: clock)
                            .modifier(BlinkWhilePaused(active: session.isPaused))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .accessibilityLabel(TimeFormat.spoken(session.remaining(at: context.date)))
                    }

                    HStack {
                        Text(endsLine)
                            .font(.system(size: height * 0.06, weight: .medium, design: .rounded))
                            .monospacedDigit()
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
                    }

                    SessionPills(completed: today.count,
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
    }

    private var endsLine: String {
        if session.isPaused { return "Tap play to resume" }
        guard let end = session.endDate else { return "" }
        return session.phase == .focus ? "Ends \(TimeFormat.time(end))" : "Break until \(TimeFormat.time(end))"
    }
}
