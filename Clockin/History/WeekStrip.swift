import SwiftUI

/// A week as seven pill columns: each day's focus sessions fill a column of
/// four from the bottom, in the same colours and states as the session
/// pills everywhere else. Today is marked with a dot.
struct WeekStrip: View {
    let totals: [DayTotal]
    /// From `AppServices.today`, so the marker moves at midnight.
    let today: Date
    let calendar: Calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(totals.enumerated()), id: \.offset) { index, entry in
                let isToday = calendar.isDate(entry.day, inSameDayAs: today)
                let isFuture = entry.day > today && !isToday
                VStack(spacing: 8) {
                    Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.retro(.label))
                        .foregroundStyle(isToday ? Retro.ink : Retro.inkSoft)
                    SessionPills(completed: appeared ? entry.sessions : 0,
                                 pillWidth: 24, pillHeight: 7, axis: .vertical)
                        .opacity(isFuture ? 0.4 : 1)
                        .animation(Motion.wind(reduceMotion).delay(reduceMotion ? 0 : 0.05 * Double(index)),
                                   value: appeared)
                    Circle()
                        .fill(Retro.orange)
                        .frame(width: 5, height: 5)
                        .opacity(isToday ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.accessibilityText(entry, today: today, calendar: calendar))
            }
        }
        .onAppear { appeared = true }
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
