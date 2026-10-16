import Foundation

/// The next planned session, as the Lock Screen and the widget show it:
/// its name and its symbol. Only while today's plan has one to do.
struct NextUp: Codable, Hashable, Sendable {
    var name: String
    var symbol: String
}
