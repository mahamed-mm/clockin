import SwiftData
import SwiftUI

/// One subject's page in History: facts about everything saved under its
/// name, the last three months as small dials for this subject alone, the
/// latest sessions and the thoughts still open from them. Facts only:
/// nothing to beat, nothing compared.
struct SubjectPage: View {
    let route: SubjectRoute
    /// Opens a session's card.
    let open: (OpenedCard) -> Void
    /// Back to the week, showing only this subject.
    let showInWeek: () -> Void
    @Environment(AppServices.self) private var services
    /// Every spelling of the name, looked up once the page opens.
    @State private var spellings: Set<String>?

    var body: some View {
        Group {
            if let spellings {
                SubjectPageContent(route: route, spellings: spellings, open: open, showInWeek: showInWeek)
            } else {
                Color.clear
            }
        }
        .background(PaperBackground().paperGrain())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.key) {
            spellings = (try? services.history?.spellings(of: route.key)) ?? [route.name]
        }
    }
}

private struct SubjectPageContent: View {
    let route: SubjectRoute
    let open: (OpenedCard) -> Void
    let showInWeek: () -> Void
    @Query private var records: [FocusRecord]
    @Environment(AppServices.self) private var services
    @Environment(SessionEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var badge: CGFloat = 52

    init(route: SubjectRoute, spellings: Set<String>, open: @escaping (OpenedCard) -> Void,
         showInWeek: @escaping () -> Void) {
        self.route = route
        self.open = open
        self.showInWeek = showInWeek
        _records = Query(filter: #Predicate<FocusRecord> { spellings.contains($0.name) },
                         sort: \.completedAt, order: .reverse)
    }

    /// Saved sessions, and any still waiting to be saved, each once.
    private var history: SubjectHistory {
        let saved = Set(records.map(\.id))
        let sessions = records.map {
            SubjectHistory.Session(id: $0.id, name: $0.name, startedAt: $0.startedAt, completedAt: $0.completedAt,
                                   seconds: $0.focusSeconds, plannedSeconds: $0.plannedSeconds)
        } + engine.pendingRecords.filter { !saved.contains($0.id) }.map {
            SubjectHistory.Session(id: $0.id, name: $0.name, startedAt: $0.startedAt, completedAt: $0.completedAt,
                                   seconds: $0.focusSeconds, plannedSeconds: $0.plannedSeconds)
        }
        return SubjectHistory(key: route.key, sessions: sessions)
    }

    var body: some View {
        let history = history
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header(history)
                if !history.sessions.isEmpty {
                    months(history)
                    recent(history)
                }
                thoughts(history)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
            .transition(.rise(reduceMotion))
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Header and facts

    private func header(_ history: SubjectHistory) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Image(systemName: services.symbol(for: history.name))
                .font(.title2.weight(.semibold))
                .foregroundStyle(Retro.ink)
                .frame(width: badge, height: badge)
                .background(Retro.ink.opacity(0.1), in: .circle)
                .accessibilityHidden(true)
            Text(Copy.displayName(history.name))
                .retroFont(.title)
                .foregroundStyle(Retro.ink)
                .accessibilityAddTraits(.isHeader)
            if let first = history.firstDate {
                Text(Copy.subjectTotal(seconds: history.totalSeconds, sessions: history.sessionCount, since: first))
                    .font(.retro(.body))
                    .foregroundStyle(Retro.ink)
                    .accessibilityLabel(Copy.subjectTotalSpoken(seconds: history.totalSeconds,
                                                                sessions: history.sessionCount, since: first))
            }
            if let length = history.typicalLength {
                let part = history.usualPart(calendar: services.calendar)
                Text(Copy.subjectHabit(part: part, length: TimeFormat.duration(length)))
                    .font(.retro(.body))
                    .foregroundStyle(Retro.inkSoft)
                    .accessibilityLabel(Copy.subjectHabit(part: part, length: TimeFormat.spokenDuration(length)))
            }
            Button(Copy.showInWeek, systemImage: "calendar", action: showInWeek)
                .font(.retro(.meta).weight(.semibold))
                .foregroundStyle(Retro.orangeText)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.xs)
    }

    // MARK: Months

    private func months(_ history: SubjectHistory) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(Copy.lastThreeMonths)
                .retroLabel()
                .accessibilityAddTraits(.isHeader)
            ForEach(history.months(endingAt: services.today, calendar: services.calendar), id: \.month.start) {
                entry in
                SubjectMonth(month: entry.month, days: entry.days, today: services.today, calendar: services.calendar)
            }
        }
    }

    // MARK: Recent sessions

    private func recent(_ history: SubjectHistory) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(Copy.recentSessions)
                .retroLabel()
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(history.recent) { session in
                    Button { openCard(session.id) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text(session.completedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                .font(.retro(.meta))
                                .foregroundStyle(Retro.inkSoft)
                            Spacer(minLength: Space.xs)
                            Text(TimeFormat.duration(session.seconds))
                                .retroFont(.headline)
                                .foregroundStyle(Retro.orangeText)
                                .retroNumber()
                        }
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: """
                        \(session.completedAt.formatted(.dateTime.weekday(.wide).day().month(.wide))), \
                        \(TimeFormat.spokenDuration(session.seconds))
                        """))
                    .accessibilityHint(String(localized: "Shows the session, to rename or delete it"))
                    if session.id != history.recent.last?.id {
                        Rectangle().fill(Retro.ink.opacity(0.1)).frame(height: 1).padding(.leading, Space.m)
                    }
                }
            }
            .background(Retro.ink.opacity(0.06), in: .rect(cornerRadius: Radius.card))
        }
    }

    private func openCard(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        open(OpenedCard(SessionSummary(record)))
    }

    // MARK: Open thoughts

    @ViewBuilder
    private func thoughts(_ history: SubjectHistory) -> some View {
        let open = history.sessions.flatMap { services.thoughts.thoughts(for: $0.id) }.filter { $0.done != true }
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Copy.openThoughtsTitle)
                    .retroLabel()
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(open) { thought in
                        Button { services.setThoughtDone(true, thought.id) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                Image(systemName: "circle")
                                    .foregroundStyle(Retro.ink)
                                Text(thought.text)
                                    .font(.retro(.body))
                                    .foregroundStyle(Retro.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(thought.text)
                        .accessibilityHint(Copy.markDone)
                    }
                }
                .padding(Space.m)
                .background(Retro.ink.opacity(0.06), in: .rect(cornerRadius: Radius.card))
            }
        }
    }
}

/// One month of a subject: a small dial for each day, filled to that day's
/// sessions of it out of four. All in ink, never the set colours: these
/// sessions weren't necessarily those places in the day's set. At the
/// largest text sizes, the days with sessions as a list.
private struct SubjectMonth: View {
    let month: DateInterval
    let days: [Date: DayTotal]
    let today: Date
    let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var dayNumber: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(month.start.formatted(.dateTime.month(.wide).year()))
                .font(.retro(.meta))
                .foregroundStyle(Retro.inkSoft)
                .accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                list
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        VStack(spacing: Space.xxs) {
            ForEach(Array(MonthGrid.rows(month: month, calendar: calendar).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(day)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func cell(_ day: Date) -> some View {
        let entry = days[calendar.startOfDay(for: day)]
        return ZStack {
            RetroDial(value: min(1, Double(entry?.sessions ?? 0) / Double(TimerPlan.sessionsPerSet)),
                      tint: Retro.inkSoft, glowTint: Retro.ink, showsTicks: false, showsKnob: false,
                      lineWidthRatio: 0.12)
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: dayNumber, weight: entry == nil ? .regular : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry == nil ? Retro.inkSoft.opacity(0.7) : Retro.ink)
        }
        .frame(maxWidth: 34)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.map { WeekStrip.accessibilityText($0, today: today, calendar: calendar) } ?? "")
        .accessibilityHidden(entry == nil)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(days.values.sorted { $0.day < $1.day }, id: \.day) { entry in
                HStack(spacing: Space.s) {
                    RetroDial(value: min(1, Double(entry.sessions) / Double(TimerPlan.sessionsPerSet)),
                              tint: Retro.inkSoft, glowTint: Retro.ink, showsTicks: false, showsKnob: false,
                              lineWidthRatio: 0.14)
                        .frame(width: 44, height: 44)
                    Text(WeekStrip.accessibilityText(entry, today: today, calendar: calendar))
                        .font(.retro(.body))
                        .foregroundStyle(Retro.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
