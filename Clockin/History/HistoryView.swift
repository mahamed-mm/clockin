import SwiftData
import SwiftUI

/// Today's total up top, then one week at a time: the week strip and that
/// week's sessions by day. Paging back reaches every session ever saved.
struct HistoryView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(HistoryView.newestFirst) private var newest: [FocusRecord]
    @Query(HistoryView.oldestFirst) private var oldest: [FocusRecord]
    /// A day in the week shown, or nil to follow the current week.
    @State private var shownDay: Date?
    /// The day picked in the week strip or the month; nil for the week's own.
    @State private var pickedDay: Date?
    /// A day in the month shown, or nil to follow the current month.
    @State private var shownMonth: Date?
    @SceneStorage("history.mode") private var mode: HistoryMode = .week
    /// The month's day being opened, which morphs into its week column.
    @State private var morphDay: Date?
    @Namespace private var morph

    private static var newestFirst: FetchDescriptor<FocusRecord> { firstRecord(order: .reverse) }
    private static var oldestFirst: FetchDescriptor<FocusRecord> { firstRecord(order: .forward) }

    private static func firstRecord(order: SortOrder) -> FetchDescriptor<FocusRecord> {
        var descriptor = FetchDescriptor<FocusRecord>(sortBy: [SortDescriptor(\.completedAt, order: order)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List {
                    Section {
                        HistoryHeader(day: services.today, calendar: services.calendar,
                                      showsTotals: !services.historyUnavailable)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: Space.xs, leading: 0, bottom: Space.xxs, trailing: 0))
                    }
                    .listRowSeparator(.hidden)

                    if services.historyUnavailable {
                        Section {
                            ContentUnavailableView {
                                Label("History couldn't be loaded", systemImage: "exclamationmark.triangle")
                            } description: {
                                Text("Your saved sessions haven't been deleted. Timers still work, and new sessions are kept until History opens again.")
                                    .font(.retro(.body))
                            }
                            .foregroundStyle(Retro.inkSoft)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        switch mode {
                        case .week:
                            HistoryWeek(week: week, today: services.today, calendar: services.calendar,
                                        canGoBack: canGoBack, canGoForward: canGoForward, page: page,
                                        scroll: scroll, pickedDay: $pickedDay, morph: reduceMotion ? nil : morph,
                                        modePicker: AnyView(modePicker))
                        case .month:
                            HistoryMonth(month: month, today: services.today, calendar: services.calendar,
                                         canGoBack: canGoBackMonth, canGoForward: canGoForwardMonth,
                                         page: pageMonth, pick: openDay, morph: reduceMotion ? nil : morph,
                                         morphDay: morphDay, modePicker: AnyView(modePicker))
                        }
                        if newest.isEmpty {
                            Section {
                                ContentUnavailableView {
                                    VStack(spacing: Space.s) {
                                        TickView(pose: .hello)
                                            .frame(width: 104, height: 104)
                                        Text("No sessions yet")
                                    }
                                } description: {
                                    Text("Finish a focus session and it will show up here.")
                                        .font(.retro(.body))
                                }
                                .foregroundStyle(Retro.inkSoft)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            // The same edge as the Focus screen, so the titles line up.
            .contentMargins(.horizontal, Space.gutter, for: .scrollContent)
            .background(PaperBackground().paperGrain())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !services.undoableDeletion.isEmpty {
                    UndoBar(message: String(localized: "Session deleted"),
                            hint: String(localized: "Puts the session back"), undo: services.undoDelete)
                        .padding(.horizontal, Space.l)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, Space.xs)
                        .transition(.bar(reduceMotion))
                }
            }
            .animation(Motion.calm(reduceMotion), value: services.undoableDeletion.isEmpty)
        }
    }

    // MARK: Week or month

    private var modePicker: some View {
        GlassEffectContainer(spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                ForEach(HistoryMode.allCases, id: \.self) { choice in
                    Button {
                        if choice == .month { shownMonth = shownDay }
                        withAnimation(Motion.calm(reduceMotion)) { mode = choice }
                    } label: {
                        Text(choice.title)
                            .font(.retro(.meta))
                            .foregroundStyle(Retro.ink)
                            .retroChip(selected: mode == choice)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == choice ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var month: DateInterval {
        services.calendar.monthInterval(containing: shownMonth ?? services.today)
    }

    private var canGoBackMonth: Bool {
        oldest.first.map { $0.completedAt < month.start } ?? false
    }

    private var canGoForwardMonth: Bool {
        month.end <= services.today
    }

    private func pageMonth(by months: Int) {
        guard let day = services.calendar.date(byAdding: .month, value: months, to: month.start) else { return }
        shownMonth = services.calendar.monthInterval(containing: day).includes(services.today) ? nil : day
    }

    /// A day tapped in the month: its week, with that day picked. The cell
    /// is marked first, so it can morph into the week's column.
    private func openDay(_ day: Date) {
        morphDay = day
        Task { @MainActor in
            withAnimation(Motion.calm(reduceMotion)) {
                shownDay = services.calendar.weekInterval(containing: day).includes(services.today) ? nil : day
                pickedDay = day
                mode = .week
            }
        }
    }

    // MARK: Paging

    private var week: DateInterval {
        services.calendar.weekInterval(containing: shownDay ?? services.today)
    }

    private var canGoBack: Bool {
        oldest.first.map { $0.completedAt < week.start } ?? false
    }

    private var canGoForward: Bool {
        week.end <= services.today
    }

    private func page(by weeks: Int) {
        guard let day = services.calendar.date(byAdding: .weekOfYear, value: weeks, to: week.start) else { return }
        // Back on this week, follow it again so it moves on at midnight.
        shownDay = services.calendar.weekInterval(containing: day).includes(services.today) ? nil : day
        pickedDay = nil
    }
}

enum HistoryMode: String, CaseIterable {
    case week, month

    var title: String {
        switch self {
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        }
    }
}

// MARK: - Header

/// "History", today's minutes and today's pills. Today only, whatever week
/// is shown below.
private struct HistoryHeader: View {
    let showsTotals: Bool
    private let day: Date
    @Query private var records: [FocusRecord]
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(day: Date, calendar: Calendar, showsTotals: Bool) {
        self.day = day
        self.showsTotals = showsTotals
        _records = Query(filter: FocusRecord.completed(on: day, calendar: calendar))
    }

    var body: some View {
        let today = TodayStats.rows(saved: records.map(\.row), pending: engine.pendingRecords(on: day))
        let total = Text(TimeFormat.duration(today.totalSeconds))
            .font(.retro(.headline, bold: legibilityWeight == .bold))
            .foregroundStyle(Retro.orangeText)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .top) {
                Text("History")
                    .retroFont(.title)
                    .foregroundStyle(Retro.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s)
                // Small and still, for company; large text needs the room more.
                if !dynamicTypeSize.isAccessibilitySize {
                    let pose = TickPose.forHistory(engine.stage, fullToday: today.fullCount,
                                                   hour: services.calendar.component(.hour, from: .now))
                    TickView(pose: pose, progress: .fixed(TickPose.ringProgress(for: engine.stage, at: .now)))
                        .environment(\.tickReduceMotion, true)
                        .frame(width: 56, height: 56)
                        .padding(.top, -Space.xxs)
                }
            }
            if showsTotals {
                Text("You focused \(total) today.")
                    .font(.retro(.headline, bold: legibilityWeight == .bold))
                    .foregroundStyle(Retro.inkSoft)
                    .contentTransition(.numericText())
                    .accessibilityLabel("You focused \(TimeFormat.spokenDuration(today.totalSeconds)) today.")
                SessionPills(completed: today.fullCount, pillWidth: 26, pillHeight: 7,
                             showsCaption: true)
                    .padding(.top, Space.xs)
            }
        }
    }
}

// MARK: - Week

/// One week: its strip with paging, then its sessions by day, newest first.
private struct HistoryWeek: View {
    let week: DateInterval
    let today: Date
    let calendar: Calendar
    let canGoBack: Bool
    let canGoForward: Bool
    let page: (Int) -> Void
    let scroll: ScrollViewProxy
    /// The day tapped in the strip or the month; nil for the week's own default.
    @Binding var pickedDay: Date?
    let morph: Namespace.ID?
    /// Week or month, above the pager.
    let modePicker: AnyView
    @Query private var records: [FocusRecord]
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// The session whose card is open.
    @State private var opened: SessionSummary?

    init(week: DateInterval, today: Date, calendar: Calendar, canGoBack: Bool, canGoForward: Bool,
         page: @escaping (Int) -> Void, scroll: ScrollViewProxy, pickedDay: Binding<Date?>, morph: Namespace.ID?,
         modePicker: AnyView) {
        self.week = week
        self.today = today
        self.calendar = calendar
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.page = page
        self.scroll = scroll
        _pickedDay = pickedDay
        self.morph = morph
        self.modePicker = modePicker
        _records = Query(filter: FocusRecord.completed(in: week), sort: \.completedAt, order: .reverse)
    }

    var body: some View {
        Section {
            VStack(spacing: Space.s) {
                modePicker
                HistoryPager(title: weekTitle, previous: String(localized: "Previous week"),
                             next: String(localized: "Next week"), canGoBack: canGoBack, canGoForward: canGoForward,
                             page: page)
                WeekStrip(totals: totals, today: today, calendar: calendar, selected: selectedDay,
                          select: select, morph: morph)
                    // A new week fills in afresh.
                    .id(week.start)
                if let selectedDay {
                    DayRibbon(title: dayTitle(selectedDay), sessions: ribbon(on: selectedDay), day: selectedDay,
                              calendar: calendar, open: open)
                        .padding(.top, Space.xxs)
                        // Each day draws in afresh.
                        .id(selectedDay)
                        .transition(.opacity)
                }
                if let facts {
                    WeekSentenceLine(facts: facts, calendar: calendar)
                        .id(week.start)
                        .transition(.opacity)
                }
                let subjects = subjectTotals
                if !subjects.top.isEmpty {
                    WeekSubjects(totals: subjects)
                        .padding(.top, Space.xs)
                        .id(week.start)
                        .transition(.opacity)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.xs, leading: 0, bottom: Space.s, trailing: 0))
            .onAppear { appeared = true }
            .animation(Motion.calm(reduceMotion), value: selectedDay)
        }
        .listRowSeparator(.hidden)

        if records.isEmpty && !week.includes(today) {
            Section {
                Text("No sessions this week.")
                    .font(.retro(.body))
                    .foregroundStyle(Retro.inkSoft)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }

        ForEach(Array(days.enumerated()), id: \.element.day) { dayIndex, group in
            Section {
                ForEach(Array(group.records.enumerated()), id: \.element.id) { rowIndex, record in
                    // A real button, so Full Keyboard Access and Switch Control reach it too.
                    Button { opened = SessionSummary(record) } label: {
                        SessionRow(record: record)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "Shows the session, to rename or delete it"))
                    .accessibilityInputLabels([Copy.displayName(record.name)])
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                services.deleteSessions([record.id])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 10)
                        .animation(Motion.calm(reduceMotion)
                            .delay(Motion.stagger(dayIndex * 3 + rowIndex, reduceMotion)), value: appeared)
                }
            } header: {
                HStack {
                    Text(dayTitle(group.day)).retroLabel()
                    Spacer()
                    Text(TimeFormat.duration(group.records.reduce(0) { $0 + $1.focusSeconds }))
                        .font(.retro(.meta))
                        .foregroundStyle(Retro.inkSoft)
                }
            }
            .listRowBackground(Retro.paperDeep.opacity(0.6))
            .id(Self.sectionID(group.day))
        }
        .sheet(item: $opened) { summary in
            SessionCard(summary: summary, now: today, calendar: calendar,
                        symbol: services.symbol(for: summary.name),
                        rename: { services.renameSession(summary.id, to: $0) },
                        setSymbol: { services.setSymbol($0, for: summary.name) },
                        delete: { services.deleteSessions([summary.id]) })
                .fittedSheet()
        }
    }

    private var selectedDay: Date? {
        pickedDay ?? WeekStrip.defaultDay(totals, today: today, calendar: calendar)
    }

    private static func sectionID(_ day: Date) -> String { "day-\(day.timeIntervalSinceReferenceDate)" }

    private func select(_ day: Date) {
        pickedDay = day
        guard let group = days.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) else { return }
        withAnimation(Motion.calm(reduceMotion)) { scroll.scrollTo(Self.sectionID(group.day), anchor: .top) }
    }

    /// The day's sessions for its ribbon, saved or waiting.
    private func ribbon(on day: Date) -> [DayRibbonLayout.Session] {
        let saved = records.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }
        let ids = Set(saved.map(\.id))
        let waiting = engine.pendingRecords(on: day).filter { !ids.contains($0.id) }
        return saved.map {
            DayRibbonLayout.Session(id: $0.id, name: $0.name, startedAt: $0.startedAt, completedAt: $0.completedAt,
                                    seconds: $0.focusSeconds, countsAsFull: $0.row.countsAsFull)
        } + waiting.map {
            DayRibbonLayout.Session(id: $0.id, name: $0.name, startedAt: $0.startedAt, completedAt: $0.completedAt,
                                    seconds: $0.focusSeconds, countsAsFull: $0.countsAsFull)
        }
    }

    /// Opens a session's card from the ribbon; one still waiting to be saved has none.
    private func open(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        opened = SessionSummary(record)
    }

    /// "This week", "Last week", or "28 Sept – 4 Oct".
    private var weekTitle: String {
        if week.includes(today) { return String(localized: "This week") }
        if let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week.start),
           calendar.weekInterval(containing: next).includes(today) {
            return String(localized: "Last week")
        }
        let lastDay = week.end.addingTimeInterval(-1)
        return (week.start..<lastDay).formatted(.interval.day().month(.abbreviated))
    }

    private var totals: [DayTotal] {
        TodayStats.weekTotals(saved: records.map(\.row), pending: engine.pendingRecords,
                              containing: week.start, calendar: calendar)
    }

    /// The week's minutes by name, saved or waiting.
    private var subjectTotals: SubjectTotals {
        let savedIDs = Set(records.map(\.id))
        let waiting = engine.pendingRecords.filter { week.includes($0.completedAt) && !savedIDs.contains($0.id) }
        return SubjectTotals(records.map {
            SubjectTotals.Session(name: $0.name, completedAt: $0.completedAt, seconds: $0.focusSeconds)
        } + waiting.map {
            SubjectTotals.Session(name: $0.name, completedAt: $0.completedAt, seconds: $0.focusSeconds)
        })
    }

    /// The week's focus, saved or still waiting to be saved, each once.
    private var facts: WeekFacts? {
        let savedIDs = Set(records.map(\.id))
        let waiting = engine.pendingRecords.filter { week.includes($0.completedAt) && !savedIDs.contains($0.id) }
        let sessions = records.map {
            WeekFacts.Session(startedAt: $0.startedAt, completedAt: $0.completedAt, seconds: $0.focusSeconds)
        } + waiting.map {
            WeekFacts.Session(startedAt: $0.startedAt, completedAt: $0.completedAt, seconds: $0.focusSeconds)
        }
        return WeekFacts(sessions: sessions, calendar: calendar)
    }

    private var days: [(day: Date, records: [FocusRecord])] {
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.completedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDate(day, inSameDayAs: today) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

/// TIDE-style log row: time, name, minutes.
private struct SessionRow: View {
    let record: FocusRecord
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Every symbol in the same width, so names line up.
    @ScaledMetric(relativeTo: .footnote) private var symbolWidth: CGFloat = 22

    var body: some View {
        // Time, name and minutes in a row, or stacked at large text sizes
        // so the name isn't squeezed to nothing.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.s))
        layout {
            Text(TimeFormat.time(record.completedAt))
                .font(.retro(.meta))
                .foregroundStyle(Retro.inkSoft)
                .frame(minWidth: 52, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Image(systemName: services.symbol(for: record.name))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Retro.inkSoft)
                    .frame(width: symbolWidth)
                Text(Copy.displayName(record.name))
                    .retroFont(.headline)
                    .foregroundStyle(Retro.ink)
                    .lineLimit(stacked ? nil : 1)
                    .minimumScaleFactor(stacked ? 1 : 0.85)
            }
            if !stacked { Spacer(minLength: 8) }
            Text(TimeFormat.duration(record.focusSeconds))
                .retroFont(.headline)
                .foregroundStyle(Retro.orangeText)
                .retroNumber()
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: """
            \(Copy.displayName(record.name)), \(TimeFormat.spokenDuration(record.focusSeconds)), \
            finished at \(TimeFormat.time(record.completedAt))
            """))
    }
}
