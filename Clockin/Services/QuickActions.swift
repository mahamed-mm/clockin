import SwiftUI
import UIKit

/// The Home Screen's quick actions (touch and hold the icon): when idle,
/// start one of the last two sessions again, or open History; during focus,
/// pause, park a thought, or open History. Never a thought's text.
enum QuickAction: Equatable, Sendable {
    case start(name: String)
    case pause
    case park
    case history

    private static let prefix = "com.moha.clockin."
    private static let nameKey = "name"

    var type: String {
        switch self {
        case .start: Self.prefix + "start"
        case .pause: Self.prefix + "pause"
        case .park: Self.prefix + "park"
        case .history: Self.prefix + "history"
        }
    }

    init?(type: String, userInfo: [String: any NSSecureCoding]?) {
        switch type {
        case Self.prefix + "start": self = .start(name: userInfo?[Self.nameKey] as? String ?? "")
        case Self.prefix + "pause": self = .pause
        case Self.prefix + "park": self = .park
        case Self.prefix + "history": self = .history
        default: return nil
        }
    }

    init?(_ item: UIApplicationShortcutItem) {
        self.init(type: item.type, userInfo: item.userInfo)
    }

    /// What the icon offers now.
    static func available(focusing: Bool, recentNames: [String]) -> [QuickAction] {
        if focusing { return [.pause, .park, .history] }
        return recentNames.prefix(2).map { .start(name: $0) } + [.history]
    }

    var title: String {
        switch self {
        case .start(let name): Copy.startNamed(Copy.displayName(name))
        case .pause: String(localized: "Pause")
        case .park: Copy.parkThought
        case .history: String(localized: "History")
        }
    }

    func shortcutItem(symbol: (String) -> String) -> UIApplicationShortcutItem {
        let icon: String
        var userInfo: [String: any NSSecureCoding]?
        switch self {
        case .start(let name):
            icon = symbol(name)
            userInfo = [Self.nameKey: name as NSString]
        case .pause: icon = "pause.fill"
        case .park: icon = "note.text"
        case .history: icon = "clock.arrow.circlepath"
        }
        return UIApplicationShortcutItem(type: type, localizedTitle: title, localizedSubtitle: nil,
                                         icon: UIApplicationShortcutIcon(systemImageName: icon), userInfo: userInfo)
    }
}

/// Hands a quick action from the scene delegate to the app.
@MainActor
enum QuickActionInbox {
    /// Set when one arrives; `RootView` takes it.
    static var pending: QuickAction? {
        didSet { if pending != nil { NotificationCenter.default.post(name: arrived, object: nil) } }
    }
    static let arrived = Notification.Name("clockin.quickAction")
}

/// Takes quick actions, on a cold launch and while running.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem, let action = QuickAction(item) else { return }
        MainActor.assumeIsolated { QuickActionInbox.pending = action }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard let action = QuickAction(shortcutItem) else { return completionHandler(false) }
        MainActor.assumeIsolated { QuickActionInbox.pending = action }
        completionHandler(true)
    }
}
