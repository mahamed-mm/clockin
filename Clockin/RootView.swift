import SwiftUI

enum AppTab: Hashable {
    case focus, history
}

struct RootView: View {
    @State private var tab: AppTab = .focus
    @Environment(SessionEngine.self) private var engine

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
        // Away from Focus, a running session stays in sight above the tab bar.
        .modifier(RunningSessionAccessory(isEnabled: engine.active != nil && tab != .focus) { tab = .focus })
        .tint(Retro.orangeText)
        .onOpenURL { url in
            if url.scheme == "clockin" { tab = url.host() == "history" ? .history : .focus }
        }
    }
}

/// The running-session chip in the tab bar's accessory slot. The slot can
/// only be switched off from iOS 26.1; on 26.0 it would always show an
/// empty capsule, so there it's left out.
private struct RunningSessionAccessory: ViewModifier {
    let isEnabled: Bool
    let open: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) {
                RunningSessionChip(open: open)
            }
        } else {
            content
        }
    }
}

/// Phase, name and time left; a tap goes back to Focus. Collapsed beside
/// the tab bar it shows just the phase and the time.
private struct RunningSessionChip: View {
    let open: () -> Void
    @Environment(SessionEngine.self) private var engine
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let session = engine.active {
            Button(action: open) {
                HStack(spacing: Space.s) {
                    Image(systemName: session.phase.symbol)
                        .foregroundStyle(Retro.text(for: session.phase))
                        .accessibilityHidden(true)
                    if placement != .inline {
                        Text(session.phase == .focus ? Copy.displayName(session.name) : Copy.breakAfter(session.name))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Group {
                        if let end = session.endDate {
                            Text(timerInterval: Date.now...end, countsDown: true)
                        } else {
                            Text(Copy.paused)
                        }
                    }
                    .monospacedDigit()
                    .foregroundStyle(Retro.inkSoft)
                }
                .font(.retro(.body))
                .padding(.horizontal, Space.m)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Opens Focus"))
        }
    }
}
