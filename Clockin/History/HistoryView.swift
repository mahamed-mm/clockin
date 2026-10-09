import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \FocusRecord.completedAt, order: .reverse) private var records: [FocusRecord]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
                    WeekStrip(totals: weekTotals)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 12, trailing: 0))
                }
                .listRowSeparator(.hidden)

                if records.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No sessions yet", systemImage: "hourglass")
                        } description: {
                            Text("Finish a 25-minute focus session and it will show up here.")
                                .font(.retro(.body))
                        }
                        .foregroundStyle(Retro.inkSoft)
                        .listRowBackground(Color.clear)
                    }
                }

                ForEach(Array(days.enumerated()), id: \.element.day) { dayIndex, group in
                    Section {
                        ForEach(Array(group.records.enumerated()), id: \.element.id) { rowIndex, record in
                            SessionRow(record: record)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared || reduceMotion ? 0 : 10)
                                .animation(Motion.calm(reduceMotion)
                                    .delay(reduceMotion ? 0 : 0.04 * Double(min(dayIndex * 3 + rowIndex, 10))),
                                           value: appeared)
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
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { appeared = true }
        }
    }

    // MARK: Header

    private var header: some View {
        let seconds = todayRecords.reduce(0) { $0 + $1.focusSeconds }
        let total = Text(TimeFormat.duration(seconds))
            .font(.retro(.headline))
            .foregroundStyle(Retro.orange)
        return VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.retro(.title))
                .foregroundStyle(Retro.ink)
                .accessibilityAddTraits(.isHeader)
            Text("You focused \(total) today.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Retro.inkSoft)
                .contentTransition(.numericText())
            SessionPills(completed: todayRecords.count, pillWidth: 26, pillHeight: 7,
                         showsCaption: true)
                .padding(.top, 6)
        }
    }

    // MARK: Data

    private var todayRecords: [FocusRecord] {
        records.filter { Calendar.current.isDateInToday($0.completedAt) }
    }

    private var weekTotals: [DayTotal] {
        TodayStats.weekTotals(records: records.map { ($0.completedAt, $0.focusSeconds) },
                              containing: .now)
    }

    /// Records grouped by calendar day, newest first. Kept to the last 14 days.
    private var days: [(day: Date, records: [FocusRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.completedAt) }
        return grouped.keys.sorted(by: >).prefix(14).map { ($0, grouped[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

/// TIDE-style log row: time, name, minutes.
private struct SessionRow: View {
    let record: FocusRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(TimeFormat.time(record.completedAt))
                .font(.retro(.meta))
                .foregroundStyle(Retro.inkSoft)
                .frame(minWidth: 52, alignment: .leading)
            Text(record.name)
                .font(.retro(.headline))
                .foregroundStyle(Retro.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(TimeFormat.duration(record.focusSeconds))
                .font(.system(.body, design: .serif).weight(.bold))
                .foregroundStyle(Retro.orange)
                .retroNumber()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
