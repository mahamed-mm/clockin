import Foundation

/// What a break is for: resting with the mug, a short stretch led by
/// Tick, or breathing in time with a halo. Always optional, never counted.
enum BreakStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case rest
    case stretch
    case breathe

    var id: Self { self }

    var title: String {
        switch self {
        case .rest: String(localized: "Rest")
        case .stretch: String(localized: "Stretch")
        case .breathe: String(localized: "Breathe")
        }
    }

    /// A style this build doesn't know (saved by a newer one) is a rest,
    /// so the saved session around it still loads.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BreakStyle(rawValue: raw) ?? .rest
    }
}
