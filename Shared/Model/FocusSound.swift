import Foundation

/// Something to listen to through a focus session. The sounds are loops
/// made by scripts/make-focus-sounds.py; rain and the fireplace are two
/// layers each, played together, with lengths that share no factor so they
/// don't line up again for half an hour.
enum FocusSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case tickTock
    case brownNoise
    case rain
    case fireplace

    var id: Self { self }

    /// The bundled loop files (CAF, without the extension), played summed.
    var layers: [String] {
        switch self {
        case .off: []
        case .tickTock: ["focus-tick-tock"]
        case .brownNoise: ["focus-brown-noise"]
        case .rain: ["focus-rain", "focus-rain-drops"]
        case .fireplace: ["focus-fireplace", "focus-fireplace-crackle"]
        }
    }
}
