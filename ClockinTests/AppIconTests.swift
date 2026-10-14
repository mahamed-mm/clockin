import Foundation
import Testing
@testable import Clockin

@MainActor
final class SpyAppIcon: AppIconSwitching {
    var current: AppIconChoice = .atWork
    var chosen: [String?] = []

    func choose(_ choice: AppIconChoice) async {
        chosen.append(choice.iconName)
        current = choice
    }
}

/// Settings › App icon: Tick at work, or Tick on a break.
@MainActor
struct AppIconTests {
    func makeServices(_ icon: SpyAppIcon) -> AppServices {
        AppServices(container: AppServices.makeEmptyContainer(), stateStore: InMemorySessionStateStore(),
                    schedulesCompletion: false, liveActivity: SpyLiveActivity(), notifications: SpyNotifier(),
                    appIcon: icon, widgets: SpyWidgets(), haptics: SpyHaptics(), announce: { _ in })
    }

    @Test func thePickerShowsTheIconInUse() {
        let icon = SpyAppIcon()
        icon.current = .onBreak
        #expect(makeServices(icon).appIconChoice == .onBreak)
    }

    @Test func choosingSwitchesToThatIcon() async {
        let icon = SpyAppIcon()
        let services = makeServices(icon)
        await services.chooseAppIcon(.onBreak)
        #expect(icon.chosen == ["AppIconBreak"])
        #expect(services.appIconChoice == .onBreak)
        await services.chooseAppIcon(.atWork)
        #expect(icon.chosen == ["AppIconBreak", nil])
        #expect(services.appIconChoice == .atWork)
    }

    @Test func iconNamesRoundTrip() {
        for choice in AppIconChoice.allCases {
            #expect(AppIconChoice(iconName: choice.iconName) == choice)
        }
        #expect(AppIconChoice(iconName: "Something else") == .atWork)
        #expect(AppIconChoice.atWork.pose == .working)
        #expect(AppIconChoice.onBreak.pose == .onBreak)
    }
}
