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
        /// As last spelled; empty for unnamed sessions.
        var name: String
        var seconds: TimeInterval
    }

    var top: [Subject]
    /// Everything past the top ones, or nil when nothing is left over.
    var other: TimeInterval?

    init(_ sessions: [Session], limit: Int = 4) {
        let groups = Dictionary(grouping: sessions) { SymbolBook.key(for: $0.name) }
        let subjects = groups.values.map { group in
            let newest = group.max { $0.completedAt < $1.completedAt }
            return Subject(name: newest?.name ?? "", seconds: group.reduce(0) { $0 + $1.seconds })
        }
        .sorted {
            $0.seconds != $1.seconds ? $0.seconds > $1.seconds
                : Copy.displayName($0.name).localizedStandardCompare(Copy.displayName($1.name)) == .orderedAscending
        }
        top = Array(subjects.prefix(limit))
        let rest = subjects.dropFirst(limit)
        other = rest.isEmpty ? nil : rest.reduce(0) { $0 + $1.seconds }
    }
}

/// "By subject": the week's top names with their symbols and time, as thin
/// ink bars against the biggest. No other week to compare with.
struct WeekSubjects: View {
    let totals: SubjectTotals
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var symbolWidth: CGFloat = 22

    var body: some View {
        let biggest = max(totals.top.first?.seconds ?? 1, 1)
        VStack(alignment: .leading, spacing: Space.s) {
            Text("By subject")
                .retroLabel()
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(totals.top.enumerated()), id: \.offset) { _, subject in
                row(symbol: services.symbol(for: subject.name), name: Copy.displayName(subject.name),
                    seconds: subject.seconds, share: subject.seconds / biggest)
            }
            if let other = totals.other {
                row(symbol: nil, name: String(localized: "Other"), seconds: other, share: other / biggest)
            }
        }
    }

    private func row(symbol: String?, name: String, seconds: TimeInterval, share: Double) -> some View {
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
                        .foregroundStyle(Retro.ink)
                        .lineLimit(stacked ? nil : 1)
                }
                if !stacked { Spacer(minLength: Space.xs) }
                Text(TimeFormat.duration(seconds))
                    .font(.retro(.meta))
                    .foregroundStyle(Retro.inkSoft)
            }
            Capsule()
                .fill(Retro.ink.opacity(0.35))
                .frame(height: 3)
                .scaleEffect(x: max(0.02, min(1, share)), anchor: .leading)
                .padding(.leading, symbolWidth + Space.xxs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + ", " + TimeFormat.spokenDuration(seconds))
    }
}
