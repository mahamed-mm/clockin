import SwiftUI

/// A week as seven pill columns: each day's focus sessions fill a column of
/// four from the bottom, in the same colours and states as the session
/// pills everywhere else. Today is marked with a dot; a tapped day is
/// outlined.
struct WeekStrip: View {
    let totals: [DayTotal]
    /// From `AppServices.today`, so the marker moves at midnight.
    let today: Date
    let calendar: Calendar
    /// The day outlined, if any.
    var selected: Date?
    /// Called with a tapped day. Days still to come can't be picked.
    var select: ((Date) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(totals.enumerated()), id: \.offset) { index, entry in
                let isToday = calendar.isDate(entry.day, inSameDayAs: today)
                let isFuture = entry.day > today && !isToday
                let isSelected = selected.map { calendar.isDate(entry.day, inSameDayAs: $0) } ?? false
                Button { select?(entry.day) } label: {
                    column(entry, index: index, isToday: isToday, isFuture: isFuture, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .disabled(select == nil || isFuture)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityText(entry, today: today, calendar: calendar))
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityHint(isFuture ? "" : String(localized: "Shows this day"))
            }
        }
        .onAppear { appeared = true }
    }

    private func column(_ entry: DayTotal, index: Int, isToday: Bool, isFuture: Bool,
                        isSelected: Bool) -> some View {
        VStack(spacing: Space.xs) {
            Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                .font(.retro(.label))
                .fontWeight(isSelected ? .heavy : nil)
                .foregroundStyle(isToday || isSelected ? Retro.ink : Retro.inkSoft)
            SessionPills(completed: appeared ? entry.sessions : 0,
                         pillWidth: 24, pillHeight: 7, axis: .vertical)
                .opacity(isFuture ? 0.4 : 1)
                .animation(Motion.wind(reduceMotion).delay(Motion.stagger(index, reduceMotion)),
                           value: appeared)
            Circle()
                .fill(Retro.orange)
                .frame(width: 5, height: 5)
                .opacity(isToday ? 1 : 0)
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity)
        .background {
            // Outlined, not coloured, so it reads without colour too.
            Capsule()
                .strokeBorder(Retro.ink.opacity(0.7), lineWidth: 1.5)
                .padding(.horizontal, 6)
                .opacity(isSelected ? 1 : 0)
                .animation(Motion.snappy(reduceMotion), value: isSelected)
        }
        .contentShape(.rect)
    }

    /// The day a week opens on: today if it's in the week, else the
    /// latest day with sessions, else the first day.
    nonisolated static func defaultDay(_ totals: [DayTotal], today: Date, calendar: Calendar) -> Date? {
        if let day = totals.first(where: { calendar.isDate($0.day, inSameDayAs: today) }) { return day.day }
        return totals.last(where: { $0.seconds > 0 })?.day ?? totals.first?.day
    }

    /// "Monday 12 October, today: 2 sessions, 50 minutes", or "…, upcoming"
    /// for a day still to come. The date is there because the strip can
    /// show any week.
    static func accessibilityText(_ entry: DayTotal, today: Date, calendar: Calendar,
                                  locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide)
        let day = entry.day.formatted(style)
        if calendar.isDate(entry.day, inSameDayAs: today) {
            return String(localized: "\(day), today: \(Copy.sessions(entry.sessions)), \(TimeFormat.spokenDuration(entry.seconds))")
        }
        if entry.day > today {
            return String(localized: "\(day), upcoming")
        }
        return String(localized: "\(day): \(Copy.sessions(entry.sessions)), \(TimeFormat.spokenDuration(entry.seconds))")
    }
}
