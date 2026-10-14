import SwiftData
import SwiftUI

/// A month as rows of seven days from the calendar's first weekday, with
/// blanks before the 1st and after the last day. Pure, so it can be tested.
enum MonthGrid {
    nonisolated static func rows(month: DateInterval, calendar: Calendar) -> [[Date?]] {
        var days: [Date] = []
        var day = month.start
        while day < month.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        guard let first = days.first else { return [] }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading) + days
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    /// The weekday initials in the calendar's order, e.g. M T W T F S S.
    nonisolated static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

extension Calendar {
    /// The month containing `date`.
    func monthInterval(containing date: Date) -> DateInterval {
        if let month = dateInterval(of: .month, for: date) { return month }
        let start = startOfDay(for: date)
        return DateInterval(start: start, end: self.date(byAdding: .month, value: 1, to: start) ?? start)
    }
}

/// One month: each day a small dial filled to its sessions out of four.
/// Tapping a day opens its week with that day picked.
struct HistoryMonth: View {
    let month: DateInterval
    let today: Date
    let calendar: Calendar
    let canGoBack: Bool
    let canGoForward: Bool
    let page: (Int) -> Void
    let pick: (Date) -> Void
    /// Shared with the week strip, so a picked day morphs into its column.
    let morph: Namespace.ID?
    let morphDay: Date?
    /// Week or month, above the pager.
    let modePicker: AnyView
    @Query private var records: [FocusRecord]
    @Environment(SessionEngine.self) private var engine
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var dayNumber: CGFloat = 13

    init(month: DateInterval, today: Date, calendar: Calendar, canGoBack: Bool, canGoForward: Bool,
         page: @escaping (Int) -> Void, pick: @escaping (Date) -> Void, morph: Namespace.ID?, morphDay: Date?,
         modePicker: AnyView) {
        self.month = month
        self.today = today
        self.calendar = calendar
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.page = page
        self.pick = pick
        self.morph = morph
        self.morphDay = morphDay
        self.modePicker = modePicker
        _records = Query(filter: FocusRecord.completed(in: month), sort: \.completedAt)
    }

    var body: some View {
        Section {
            VStack(spacing: Space.s) {
                modePicker
                HistoryPager(title: month.start.formatted(.dateTime.month(.wide).year()),
                             previous: String(localized: "Previous month"), next: String(localized: "Next month"),
                             canGoBack: canGoBack, canGoForward: canGoForward, page: page)
                if dynamicTypeSize.isAccessibilitySize {
                    dayList
                } else {
                    grid
                }
                Text(verbatim: "\(Copy.sessions(totals.reduce(0) { $0 + $1.sessions })) · "
                     + TimeFormat.duration(totals.reduce(0) { $0 + $1.seconds }))
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.xs, leading: 0, bottom: Space.s, trailing: 0))
        }
        .listRowSeparator(.hidden)
    }

    private var grid: some View {
        let byDay = Dictionary(totals.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(spacing: Space.xs) {
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.retro(.label))
                        .foregroundStyle(Retro.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(MonthGrid.rows(month: month, calendar: calendar).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(byDay[day] ?? DayTotal(day: day, seconds: 0, sessions: 0))
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ entry: DayTotal) -> some View {
        let isToday = calendar.isDate(entry.day, inSameDayAs: today)
        let isFuture = entry.day > today && !isToday
        return Button { pick(entry.day) } label: {
            VStack(spacing: 3) {
                ZStack {
                    RetroDial(value: min(1, Double(entry.sessions) / Double(TimerPlan.sessionsPerSet)),
                              tint: Retro.orange, showsTicks: false, showsKnob: false, lineWidthRatio: 0.12,
                              setColors: true)
                    Text(entry.day.formatted(.dateTime.day()))
                        .font(.system(size: dayNumber, weight: isToday ? .heavy : .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? Retro.ink : Retro.inkSoft)
                }
                .frame(maxWidth: 44)
                .background {
                    if let morph, let morphDay, calendar.isDate(entry.day, inSameDayAs: morphDay) {
                        Capsule().fill(.clear).matchedGeometryEffect(id: "picked", in: morph)
                    }
                }
                Circle()
                    .fill(Retro.orange)
                    .frame(width: 4, height: 4)
                    .opacity(isToday ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .opacity(isFuture ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeekStrip.accessibilityText(entry, today: today, calendar: calendar))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isFuture ? "" : String(localized: "Shows this day"))
    }

    /// At the largest text sizes: the days with sessions, one per row.
    private var dayList: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(totals.filter { $0.seconds > 0 }, id: \.day) { entry in
                Button { pick(entry.day) } label: {
                    HStack(spacing: Space.s) {
                        RetroDial(value: min(1, Double(entry.sessions) / Double(TimerPlan.sessionsPerSet)),
                                  tint: Retro.orange, showsTicks: false, showsKnob: false, lineWidthRatio: 0.14,
                                  setColors: true)
                            .frame(width: 44)
                        VStack(alignment: .leading) {
                            Text(entry.day.formatted(.dateTime.weekday(.wide).day().month()))
                                .font(.retro(.body))
                                .foregroundStyle(Retro.ink)
                            Text(Copy.sessions(entry.sessions))
                                .font(.retro(.meta))
                                .foregroundStyle(Retro.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WeekStrip.accessibilityText(entry, today: today, calendar: calendar))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private var totals: [DayTotal] {
        TodayStats.dayTotals(saved: records.map(\.row), pending: engine.pendingRecords, in: month,
                             calendar: calendar)
    }
}

/// The chevrons and title above the week strip or the month.
struct HistoryPager: View {
    let title: String
    let previous: String
    let next: String
    let canGoBack: Bool
    let canGoForward: Bool
    let page: (Int) -> Void

    var body: some View {
        HStack {
            pageButton("chevron.left", label: previous, enabled: canGoBack) { page(-1) }
            Spacer()
            Text(title)
                .retroLabel()
                .contentTransition(.opacity)
            Spacer()
            pageButton("chevron.right", label: next, enabled: canGoForward) { page(1) }
        }
    }

    private func pageButton(_ symbol: String, label: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Retro.inkSoft)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
    }
}
