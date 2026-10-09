import SwiftUI

enum AppTab: Hashable {
    case focus, history
}

struct RootView: View {
    @State private var tab: AppTab = .focus

    var body: some View {
        TabView(selection: $tab) {
            Tab("Focus", systemImage: "timer", value: .focus) {
                FocusView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Retro.orange)
        .onOpenURL { url in
            if url.scheme == "clockin" { tab = url.host() == "history" ? .history : .focus }
        }
    }
}
