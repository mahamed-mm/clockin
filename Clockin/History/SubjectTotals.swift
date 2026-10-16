import SwiftUI

/// Where a week's focus went, by name: the biggest few, then the rest
/// together. Names match the way their symbols do, and each shows as it was
/// last spelled. Pure, so it can be tested.
struct SubjectTotals: Equatable {
    struct Session {
        var name: String
        var completedAt: Date
        var seconds: TimeInterval
    }

    struct Subject: Equatable {
        /// Names match by this, as in `SymbolBook`.
        var key: String
        /// As last spelled; empty for unnamed sessions.
        var name: String
        var seconds: TimeInterval
    }

    var top: [Subject]
    /// Everything past the top ones, or nil when nothing is left over.
    var other: TimeInterval?

    init(_ sessions: [Session], limit: Int = 4) {
        let groups = Dictionary(grouping: sessions) { SymbolBook.key(for: $0.name) }
        let subjects = groups.map { key, group in
            let newest = group.max { $0.completedAt < $1.completedAt }
            return Subject(key: key, name: newest?.name ?? "", seconds: group.reduce(0) { $0 + $1.seconds })
        }
        .sorted {
            $0.seconds != $1.seconds ? $0.seconds > $1.seconds
                : Copy.displayName($0.name).localizedStandardCompare(Copy.displayName($1.name)) == .orderedAscending
        }
        top = Array(subjects.prefix(limit))
        let rest = subjects.dropFirst(limit)
        other = rest.isEmpty ? nil : rest.reduce(0) { $0 + $1.seconds }
    }

    var topKeys: Set<String> { Set(top.map(\.key)) }
}

/// A row picked in "By subject": one name, or everything past the top ones.
/// It stays picked from week to week; "Other" is worked out for each week.
enum SubjectFilter: Equatable {
    case subject(key: String, name: String)
    case other

    /// The same row, however the name was spelled in the week it was picked.
    var id: String {
        switch self {
        case .subject(let key, _): "subject:" + key
        case .other: "other"
        }
    }

    /// Whether a session called `name` belongs, in a week with these totals.
    func matches(_ name: String, in totals: SubjectTotals) -> Bool {
        let key = SymbolBook.key(for: name)
        switch self {
        case .subject(let wanted, _): return key == wanted
        case .other: return !totals.topKeys.contains(key)
        }
    }

    /// The week's days, as start of day, with none of its sessions.
    func daysWithout(_ sessions: [SubjectTotals.Session], in totals: SubjectTotals, days: [Date],
                     calendar: Calendar) -> Set<Date> {
        let with = Set(sessions.filter { matches($0.name, in: totals) }.map { calendar.startOfDay(for: $0.completedAt) })
        return Set(days.map { calendar.startOfDay(for: $0) }).subtracting(with)
    }

    /// "Chemistry", or "Other".
    var title: String {
        switch self {
        case .subject(_, let name): Copy.displayName(name)
        case .other: String(localized: "Other")
        }
    }
}

/// "By subject": the week's top names with their symbols and time, as thin
/// ink bars against the biggest. No other week to compare with. Tapping a
/// subject opens its page; "Show in week" (its long-press, and on the page)
/// shows only its sessions. "Other" isn't a subject, so a tap filters.
struct WeekSubjects: View {
    let totals: SubjectTotals
    var filter: SubjectFilter?
    var pick: (SubjectFilter) -> Void = { _ in }
    /// Opens a subject's page, by key and name.
    var open: ((String, String) -> Void)?
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var symbolWidth: CGFloat = 22

    var body: some View {
        let biggest = max(totals.top.first?.seconds ?? 1, 1)
        VStack(alignment: .leading, spacing: Space.s) {
            Text("By subject")
                .retroLabel()
                .accessibilityAddTraits(.isHeader)
            ForEach(totals.top, id: \.key) { subject in
                row(.subject(key: subject.key, name: subject.name), symbol: services.symbol(for: subject.name),
                    seconds: subject.seconds, share: subject.seconds / biggest)
            }
            if let other = totals.other {
                row(.other, symbol: nil, seconds: other, share: other / biggest)
            }
        }
    }

    private func row(_ choice: SubjectFilter, symbol: String?, seconds: TimeInterval, share: Double) -> some View {
        let picked = filter?.id == choice.id
        let subject = choice == .other ? nil : choice.title
        let page = Self.route(for: choice, opens: open != nil)
        return Button {
            if let page { open?(page.key, page.name) } else { pick(choice) }
        } label: {
            label(name: choice.title, symbol: symbol, seconds: seconds, share: share, picked: picked)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if page != nil {
                Button(picked ? Copy.showsEverySession : Copy.showInWeek, systemImage: "calendar") { pick(choice) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.title + ", " + TimeFormat.spokenDuration(seconds))
        .accessibilityHint(page.map { Copy.opensSubject($0.name) }
                           ?? (picked ? Copy.showsEverySession : Copy.showsOnly(subject)))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityInputLabels([choice.title])
        .accessibilityActions {
            if page != nil {
                Button(picked ? Copy.showsEverySession : Copy.showInWeek) { pick(choice) }
            }
        }
    }

    /// Where a row's tap goes: a subject's page, or (for Other, or with no
    /// pages to open) the filter. Pure, for the tests.
    static func route(for choice: SubjectFilter, opens: Bool) -> (key: String, name: String)? {
        guard opens, case .subject(let key, let name) = choice else { return nil }
        return (key, name)
    }

    private func label(name: String, symbol: String?, seconds: TimeInterval, share: Double,
                       picked: Bool) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xxs))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.xxs))
        return VStack(alignment: .leading, spacing: Space.xxs) {
            layout {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                    Image(systemName: symbol ?? SymbolCatalog.unnamed)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Retro.inkSoft)
                        .frame(width: symbolWidth)
                        .opacity(symbol == nil ? 0 : 1)
                    Text(name)
                        .font(.retro(.body))
                        .fontWeight(picked ? .bold : nil)
                        .foregroundStyle(Retro.ink)
                        .lineLimit(stacked ? nil : 1)
                }
                if !stacked { Spacer(minLength: Space.xs) }
                Text(TimeFormat.duration(seconds))
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
            }
            // The picked row's bar turns orange; the others keep their ink.
            Capsule()
                .fill(picked ? Retro.orange : Retro.ink.opacity(0.35))
                .frame(height: 3)
                .scaleEffect(x: max(0.02, min(1, share)), anchor: .leading)
                .padding(.leading, symbolWidth + Space.xxs)
        }
    }
}
