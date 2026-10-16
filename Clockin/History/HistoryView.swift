import SwiftData
import SwiftUI
import TipKit

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
    /// The session whose card is open. Presented from the list itself, not
    /// a row, which scrolls away (and once each day's section tried it too).
    @State private var opened: OpenedCard?
    /// The card zooms out of its row.
    @Namespace private var zoom
    /// The subject picked in "By subject". Kept when paging and in the month,
    /// so a subject can be followed back through the weeks.
    @State private var subjectFilter: SubjectFilter?
    /// Subject pages opened from the week.
    @State private var path: [SubjectRoute] = []
    /// A subject page to open once the session card it was asked for from has gone.
    @State private var subjectAfterCard: SubjectRoute?

    private static var newestFirst: FetchDescriptor<FocusRecord> { firstRecord(order: .reverse) }
    private static var oldestFirst: FetchDescriptor<FocusRecord> { firstRecord(order: .forward) }

    private static func firstRecord(order: SortOrder) -> FetchDescriptor<FocusRecord> {
        var descriptor = FetchDescriptor<FocusRecord>(sortBy: [SortDescriptor(\.completedAt, order: order)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                                        modePicker: AnyView(modePicker), opened: $opened, zoom: zoom,
                                        filter: $subjectFilter, openSubject: { path.append($0) })
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
            .navigationDestination(for: SubjectRoute.self) { route in
                SubjectPage(route: route, open: { opened = $0 }) { shown in
                    // Back to the week, showing only this subject.
                    subjectFilter = .subject(key: shown.key, name: shown.name)
                    mode = .week
                    path.removeAll()
                }
            }
            .onAppear { ClockinTips.note(ClockinTips.historyOpened) }
            .sheet(item: $opened, onDismiss: openSubjectAfterCard) { card in
                let summary = card.summary
                let key = SymbolBook.key(for: summary.name)
                SessionCard(summary: summary, now: services.today, calendar: services.calendar,
                            symbol: services.symbol(for: summary.name),
                            thoughts: services.thoughts.thoughts(for: summary.id), opening: card.mode,
                            rename: { services.renameSession(summary.id, to: $0) },
                            setSymbol: { services.setSymbol($0, for: summary.name) },
                            delete: { services.deleteSessions([summary.id]) },
                            // Not from the subject's own page: it's already open.
                            allSessions: key.isEmpty || path.last?.key == key ? nil : {
                                subjectAfterCard = SubjectRoute(key: key, name: summary.name,
                                                                zoomFrom: card.fromRow ? summary.id.uuidString : nil)
                            })
                    .fittedSheet()
                    .modifier(ZoomFromRow(id: card.id, in: zoom, enabled: card.fromRow && !reduceMotion))
            }
            // The same edge as the Focus screen, so the titles line up.
            .contentMargins(.horizontal, Space.gutter, for: .scrollContent)
            .background(PaperBackground().paperGrain())
            .toolbar(.hidden, for: .navigationBar)
        }
        // On the week and on a subject's page alike.
        .safeAreaInset(edge: .bottom) {
            if let undo = services.historyUndo {
                UndoBar(message: undoMessage(undo).message, hint: undoMessage(undo).hint,
                        undo: services.undoHistoryChange)
                    .padding(.horizontal, Space.l)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, Space.xs)
                    .transition(.bar(reduceMotion))
            }
        }
        .animation(Motion.calm(reduceMotion), value: services.historyUndo == nil)
    }

    private func openSubjectAfterCard() {
        guard let route = subjectAfterCard else { return }
        subjectAfterCard = nil
        path.append(route)
    }

    /// What the undo bar says for the change it can put back.
    private func undoMessage(_ undo: HistoryUndo) -> (message: String, hint: String) {
        switch undo {
        case .deletion:
            (String(localized: "Session deleted"), String(localized: "Puts the session back"))
        case .rename(let rename):
            (Copy.renamedTo(rename.name), Copy.putsNamesBack)
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
                                                   hour: TickPose.hour(at: .now, calendar: services.calendar))
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
    /// History's hints, one at a time.
    @State private var tips = TipGroup(.ordered) {
        HistoryTapTip()
        HistoryMenuTip()
    }
    /// The session whose card is open, and how.
    @Binding var opened: OpenedCard?
    let zoom: Namespace.ID
    /// Only this subject's sessions, when one is picked.
    @Binding var filter: SubjectFilter?
    /// Opens a subject's page.
    let openSubject: (SubjectRoute) -> Void
    @Environment(\.showFocus) private var showFocus

    init(week: DateInterval, today: Date, calendar: Calendar, canGoBack: Bool, canGoForward: Bool,
         page: @escaping (Int) -> Void, scroll: ScrollViewProxy, pickedDay: Binding<Date?>, morph: Namespace.ID?,
         modePicker: AnyView, opened: Binding<OpenedCard?>, zoom: Namespace.ID, filter: Binding<SubjectFilter?>,
         openSubject: @escaping (SubjectRoute) -> Void) {
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
        _opened = opened
        self.zoom = zoom
        _filter = filter
        self.openSubject = openSubject
        _records = Query(filter: FocusRecord.completed(in: week), sort: \.completedAt, order: .reverse)
    }

    var body: some View {
        let subjects = subjectTotals
        let shownDays = days(in: subjects)
        Section {
            VStack(spacing: Space.s) {
                modePicker
                HistoryPager(title: weekTitle, previous: String(localized: "Previous week"),
                             next: String(localized: "Next week"), canGoBack: canGoBack, canGoForward: canGoForward,
                             page: page)
                WeekStrip(totals: totals, today: today, calendar: calendar, selected: selectedDay,
                          select: select, morph: morph,
                          dimmed: filter.map { $0.daysWithout(weekSessions, in: subjects, days: totals.map(\.day),
                                                              calendar: calendar) } ?? [],
                          dimmedValue: Copy.noSessions(filter.flatMap(subjectName)))
                    // A new week fills in afresh.
                    .id(week.start)
                if let selectedDay {
                    DayRibbon(title: dayTitle(selectedDay), sessions: ribbon(on: selectedDay), day: selectedDay,
                              calendar: calendar, open: open,
                              highlights: filter.map { filter in { filter.matches($0, in: subjects) } })
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
                if !subjects.top.isEmpty {
                    WeekSubjects(totals: subjects, filter: filter, pick: pick, open: { key, name in
                        ClockinTips.note(ClockinTips.dayOrSubjectTapped)
                        openSubject(SubjectRoute(key: key, name: name, zoomFrom: SubjectRoute.rowSource(key)))
                    })
                        .padding(.top, Space.xs)
                        .id(week.start)
                        .transition(.opacity)
                }
                if let tip = tips.currentTip {
                    TipView(tip)
                        .tipViewStyle(RetroTipStyle())
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.xs, leading: 0, bottom: Space.s, trailing: 0))
            .onAppear { appeared = true }
            .animation(Motion.calm(reduceMotion), value: selectedDay)
        }
        .listRowSeparator(.hidden)

        if let filter {
            Section {
                filterChip(filter)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .transition(.opacity)
                if shownDays.isEmpty {
                    Text(Copy.noSessionsThisWeek(subjectName(filter)))
                        .font(.retro(.body))
                        .foregroundStyle(Retro.inkSoft)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .listRowSeparator(.hidden)
        } else if records.isEmpty && !week.includes(today) {
            Section {
                Text("No sessions this week.")
                    .font(.retro(.body))
                    .foregroundStyle(Retro.inkSoft)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }

        ForEach(Array(shownDays.enumerated()), id: \.element.day) { dayIndex, group in
            Section {
                ForEach(Array(group.records.enumerated()), id: \.element.id) { rowIndex, record in
                    // A real button, so Full Keyboard Access and Switch Control reach it too.
                    Button { opened = OpenedCard(SessionSummary(record), fromRow: true) } label: {
                        SessionRow(record: record)
                            .contentShape(.rect)
                    }
                    .matchedTransitionSource(id: record.id, in: zoom)
                    // The open card's row stays lit, so it's clear where the card came from.
                    .listRowBackground(Retro.paperDeep.opacity(0.6)
                        .overlay(Retro.ink.opacity(opened?.id == record.id ? 0.08 : 0))
                        .animation(Motion.calm(reduceMotion), value: opened?.id))
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "Shows the session, to rename or delete it"))
                    .accessibilityInputLabels([Copy.displayName(record.name)])
                    .contextMenu {
                        menu(for: record)
                    } preview: {
                        SessionPeek(summary: SessionSummary(record), now: today, calendar: calendar,
                                    symbol: services.symbol(for: record.name))
                    }
                    .accessibilityActions { menu(for: record) }
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
    }

    private var selectedDay: Date? {
        pickedDay ?? WeekStrip.defaultDay(totals, today: today, calendar: calendar)
    }

    private static func sectionID(_ day: Date) -> String { "day-\(day.timeIntervalSinceReferenceDate)" }

    private func select(_ day: Date) {
        ClockinTips.note(ClockinTips.dayOrSubjectTapped)
        pickedDay = day
        guard let group = days(in: subjectTotals).first(where: { calendar.isDate($0.day, inSameDayAs: day) })
        else { return }
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
        opened = OpenedCard(SessionSummary(record))
    }

    /// The row's long-press menu, also offered as VoiceOver actions.
    @ViewBuilder
    private func menu(for record: FocusRecord) -> some View {
        Button(String(localized: "Rename"), systemImage: "pencil") {
            opened = OpenedCard(SessionSummary(record), mode: .renaming)
        }
        if !SymbolBook.key(for: record.name).isEmpty {
            Button(Copy.changeSymbol, systemImage: "square.grid.2x2") {
                opened = OpenedCard(SessionSummary(record), mode: .pickingSymbol)
            }
        }
        Button(String(localized: "Start again"), systemImage: "arrow.counterclockwise") {
            if services.prepareFocus(name: record.name, planned: record.plannedSeconds) { showFocus() }
        }
        .disabled(engine.active != nil)
        Button(String(localized: "Delete"), systemImage: "trash", role: .destructive) {
            services.deleteSessions([record.id])
        }
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
        SubjectTotals(weekSessions)
    }

    /// The week's sessions by name, saved or waiting, each once.
    private var weekSessions: [SubjectTotals.Session] {
        let savedIDs = Set(records.map(\.id))
        let waiting = engine.pendingRecords.filter { week.includes($0.completedAt) && !savedIDs.contains($0.id) }
        return records.map {
            SubjectTotals.Session(name: $0.name, completedAt: $0.completedAt, seconds: $0.focusSeconds)
        } + waiting.map {
            SubjectTotals.Session(name: $0.name, completedAt: $0.completedAt, seconds: $0.focusSeconds)
        }
    }

    /// A "By subject" row tapped: only its sessions, or all of them again.
    private func pick(_ choice: SubjectFilter) {
        ClockinTips.note(ClockinTips.dayOrSubjectTapped)
        withAnimation(Motion.calm(reduceMotion)) { filter = filter?.id == choice.id ? nil : choice }
    }

    /// The subject's name for the copy; nil for "Other".
    private func subjectName(_ filter: SubjectFilter) -> String? {
        filter == .other ? nil : filter.title
    }

    /// "Chemistry ×" above the list: shows every session again.
    private func filterChip(_ filter: SubjectFilter) -> some View {
        Button {
            withAnimation(Motion.calm(reduceMotion)) { self.filter = nil }
        } label: {
            HStack(spacing: Space.xs) {
                if case .subject(_, let name) = filter {
                    Image(systemName: services.symbol(for: name))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Retro.inkSoft)
                }
                Text(filter.title)
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.ink)
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Retro.inkSoft)
            }
            .retroChip(selected: true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.showingOnly(subjectName(filter)))
        .accessibilityHint(Copy.showsEverySession)
        .accessibilityAddTraits(.isButton)
        .accessibilityInputLabels([filter.title, Copy.clearFilter])
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

    /// The sessions listed, by day: all of them, or the picked subject's.
    private func days(in subjects: SubjectTotals) -> [(day: Date, records: [FocusRecord])] {
        let shown = filter.map { filter in records.filter { filter.matches($0.name, in: subjects) } } ?? records
        let grouped = Dictionary(grouping: shown) { calendar.startOfDay(for: $0.completedAt) }
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

/// A session's card as it opens: as it is, or straight into renaming or
/// picking a symbol from the row's menu.
struct OpenedCard: Identifiable {
    var summary: SessionSummary
    var mode: SessionCard.Mode = .viewing
    /// Tapped in the list, so it can zoom out of its row.
    var fromRow = false
    var id: UUID { summary.id }

    init(_ summary: SessionSummary, mode: SessionCard.Mode = .viewing, fromRow: Bool = false) {
        self.summary = summary
        self.mode = mode
        self.fromRow = fromRow
    }
}

/// Opens the card out of its row; with Reduce Motion, the plain sheet.
private struct ZoomFromRow: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID
    let enabled: Bool

    init(id: UUID, in namespace: Namespace.ID, enabled: Bool) {
        self.id = id
        self.namespace = namespace
        self.enabled = enabled
    }

    func body(content: Content) -> some View {
        if enabled {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

