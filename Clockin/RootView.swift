import SwiftUI

enum AppTab: Hashable {
    case focus, history
}

struct RootView: View {
    @State private var tab: AppTab = .focus
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services

    var body: some View {
        TabView(selection: $tab) {
            Tab("Focus", systemImage: "timer", value: .focus) {
                FocusView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView()
                    .environment(\.showFocus, ShowFocusAction { tab = .focus })
                    // Away from Focus, a running session stays in sight above
                    // the tab bar. It floats in History's own content, not the
                    // tab bar's accessory slot: that slot widens the whole bar,
                    // so switching tabs would resize it every time.
                    .safeAreaInset(edge: .bottom) {
                        if engine.active != nil {
                            RunningSessionChip { tab = .focus }
                                .padding(.horizontal, Space.gutter)
                                .padding(.bottom, Space.xs)
                                .transition(.opacity)
                        }
                    }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Retro.orangeText)
        .onReceive(NotificationCenter.default.publisher(for: QuickActionInbox.arrived)) { _ in takeQuickAction() }
        .onAppear(perform: takeQuickAction)
        .onOpenURL { url in
            guard url.scheme == "clockin" else { return }
            tab = url.host() == "history" ? .history : .focus
            // Straight to the field, while there's a focus session to park in.
            if url.host() == "park", engine.active?.phase == .focus { services.parkFieldOpen = true }
        }
    }
}

extension RootView {
    /// A quick action from the Home Screen icon: to its tab, then done.
    private func takeQuickAction() {
        guard let action = QuickActionInbox.pending else { return }
        QuickActionInbox.pending = nil
        tab = action == .history ? .history : .focus
        services.perform(action)
    }
}

/// Switches to the Focus tab, e.g. to start a past session again.
struct ShowFocusAction {
    var action: () -> Void = {}

    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var showFocus = ShowFocusAction()
}

/// Phase, name and time left on a glass capsule; a tap goes back to Focus.
private struct RunningSessionChip: View {
    let open: () -> Void
    @Environment(SessionEngine.self) private var engine

    var body: some View {
        if let session = engine.active {
            Button(action: open) {
                HStack(spacing: Space.s) {
                    Image(systemName: session.phase.symbol)
                        .foregroundStyle(Retro.text(for: session.phase))
                        .accessibilityHidden(true)
                    Text(session.phase == .focus ? Copy.displayName(session.name) : Copy.breakAfter(session.name))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Group {
                        if let end = session.endDate {
                            Text(timerInterval: .countdown(to: end, from: .now), countsDown: true)
                        } else {
                            Text(Copy.paused)
                        }
                    }
                    .monospacedDigit()
                    .foregroundStyle(Retro.inkSoft)
                }
                .font(.retro(.body))
                .padding(.horizontal, Space.l)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(.capsule)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Opens Focus"))
        }
    }
}
