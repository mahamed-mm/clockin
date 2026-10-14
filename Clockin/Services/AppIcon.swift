import UIKit

/// The two app icons: Tick at work (the main one) and Tick on a break.
enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case atWork
    case onBreak

    var id: Self { self }

    /// The alternate icon's name, nil for the main icon.
    var iconName: String? { self == .atWork ? nil : "AppIconBreak" }

    init(iconName: String?) {
        self = iconName == "AppIconBreak" ? .onBreak : .atWork
    }

    var title: String {
        switch self {
        case .atWork: String(localized: "At work")
        case .onBreak: String(localized: "On a break")
        }
    }

    /// How Tick looks on it, for the picker's thumbnails.
    var pose: TickPose { self == .atWork ? .working : .onBreak }
}

/// Changes the Home Screen icon. A seam so tests don't touch UIApplication.
@MainActor
protocol AppIconSwitching {
    var current: AppIconChoice { get }
    func choose(_ choice: AppIconChoice) async
}

/// The real switch. iOS confirms each change with its own alert, which is
/// fine here: it only happens when someone picks an icon in Settings.
struct SystemAppIcon: AppIconSwitching {
    var current: AppIconChoice { AppIconChoice(iconName: UIApplication.shared.alternateIconName) }

    func choose(_ choice: AppIconChoice) async {
        guard choice != current else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            Log.store.error("Alternate app icons aren't supported here")
            return
        }
        Log.store.info("Switching the app icon to \(choice.rawValue, privacy: .public)")
        do {
            try await UIApplication.shared.setAlternateIconName(choice.iconName)
        } catch {
            Log.store.error("Couldn't change the app icon: \(error, privacy: .public)")
        }
    }
}
