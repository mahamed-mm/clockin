import SwiftData
import SwiftUI

struct FocusView: View {
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("lastSessionName") private var sessionName = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFocused: Bool
    @Namespace private var glass
    /// The visible area and what the pieces around the dial take, measured,
    /// so the dial gets what's left and the page scrolls when nothing is.
    @State private var viewport: CGSize = .zero
    @State private var headerHeight: CGFloat = 0
    @State private var slotHeight: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0
    /// The smallest the dial gets before the page scrolls instead; grows with text size.
    @ScaledMetric(relativeTo: .body) private var dialMinimum: CGFloat = 160
    private static let spacing = Space.l
    private static let margins = EdgeInsets(top: Space.xs, leading: Space.gutter,
                                            bottom: Space.l, trailing: Space.gutter)

    private var bedside: BedsideController { services.bedside }

    private var onItsSide: Bool { verticalSizeClass == .compact }

    /// The session as a bedside clock: chosen in Settings, or the phone
    /// turned on its side.
    private var bedsideSession: ActiveSession? {
        bedside.shows(engine.active, onItsSide: onItsSide,
                      followsRotation: services.settings.bedsideWhenSideways) ? engine.active : nil
    }

    var body: some View {
        Group {
            if let session = bedsideSession {
                BedsideView(session: session, day: services.today) {
                    bedside.leave(onItsSide: onItsSide)
                }
                .transition(.opacity)
            } else {
                standardLayout
            }
        }
        .toolbar(bedsideSession == nil ? .visible : .hidden, for: .tabBar)
        .onChange(of: BedsideController.keepsScreenOn(showing: bedsideSession != nil, session: engine.active),
                  initial: true) { _, keepOn in
            // A bedside clock stays lit while it runs; paused, the phone may sleep.
            UIApplication.shared.isIdleTimerDisabled = keepOn
        }
        .onChange(of: engine.active?.id, initial: true) { bedside.sessionChanged(to: engine.active) }
        .onChange(of: onItsSide) { _, sideways in bedside.orientationChanged(onItsSide: sideways) }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sensoryFeedback(trigger: services.lastEvent) { _, stamp in stamp.feedback }
        // VoiceOver's two-finger double tap does the main thing: start,
        // pause or resume, or start the break.
        .accessibilityAction(.magicTap) { primaryAction.2() }
        .animation(Motion.calm(reduceMotion), value: engine.stage)
        .animation(Motion.calm(reduceMotion), value: bedsideSession != nil)
    }

    private var standardLayout: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 640 || geo.size.width > geo.size.height * 1.15
            ZStack {
                PaperBackground(wash: wash)
                    .animation(Motion.tint(reduceMotion), value: engine.stage)
                    .onTapGesture { nameFocused = false }
                if wide {
                    HStack(spacing: Space.xxl) {
                        flexibleDial
                            .padding(.vertical, Space.l)
                        ScrollView {
                            VStack(alignment: .leading, spacing: Space.l) {
                                FocusHeader(stage: engine.stage)
                                sessionSlot
                                controls
                            }
                            .frame(minHeight: geo.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxWidth: 380)
                    }
                    .padding(.horizontal, Space.xl)
                } else {
                    compactLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One column. Everything stays in one scroll view whatever the size,
    /// so the name field keeps its keyboard and its glass morph; the dial
    /// takes the height left over, and below its minimum the page scrolls,
    /// which keeps Start reachable at the largest text sizes on a small phone.
    private var compactLayout: some View {
        let chrome = headerHeight + slotHeight + controlsHeight + 3 * Self.spacing
            + Self.margins.top + Self.margins.bottom
        let side = FocusLayout.dialSide(viewportHeight: viewport.height, chrome: chrome, minimum: dialMinimum,
                                        width: viewport.width - Self.margins.leading - Self.margins.trailing)
        return ScrollView {
            VStack(spacing: Self.spacing) {
                FocusHeader(stage: engine.stage)
                    .measuredHeight($headerHeight)
                DialFace(stage: engine.stage, size: side, celebration: services.celebrations)
                    .frame(maxWidth: .infinity)
                sessionSlot
                    .measuredHeight($slotHeight)
                controls
                    .measuredHeight($controlsHeight)
            }
            .padding(Self.margins)
            .frame(minHeight: viewport.height)
            .contentShape(.rect)
            .onTapGesture { nameFocused = false }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
    }

    /// A soft colour wash at the top of the page for each phase.
    private var wash: Color? {
        switch engine.stage {
        case .idle: nil
        case .active(let session): Retro.tint(for: session.phase)
        case .focusComplete: Retro.mustard
        }
    }

    /// The dial takes whatever space the header and controls leave, so the
    /// layout holds up on short folded screens and while a scene is resized.
    private var flexibleDial: some View {
        GeometryReader { proxy in
            DialFace(stage: engine.stage,
                     size: max(0, min(proxy.size.width, proxy.size.height)),
                     celebration: services.celebrations)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 160)
    }

    // MARK: Session slot

    /// Name field → session chip → completion summary. The field and chip
    /// share a Liquid Glass identity so one morphs into the other.
    @ViewBuilder
    private var sessionSlot: some View {
        GlassEffectContainer {
            switch engine.stage {
            case .idle:
                VStack(spacing: Space.s) {
                    LengthChips()
                    nameField
                        .glassEffectID("session", in: glass)
                        .glassEffectTransition(.matchedGeometry)
                    RecentNames(typed: sessionName) { sessionName = $0 }
                }
            case .active(let session):
                SessionChip(session: session)
                    .glassEffectID("session", in: glass)
                    .glassEffectTransition(.matchedGeometry)
            case .focusComplete(let focus):
                CompletionSummary(focus: focus, day: services.today)
            }
        }
    }

    private var nameField: some View {
        TextField("What are you focusing on?", text: $sessionName)
            .font(.retro(.body))
            .foregroundStyle(Retro.ink)
            .submitLabel(.go)
            .focused($nameFocused)
            .onSubmit(start)
            .onChange(of: sessionName) { _, name in
                // The engine caps names too; this keeps the field honest about it.
                if name.count > ActiveSession.maxNameLength {
                    sessionName = String(name.prefix(ActiveSession.maxNameLength))
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("Session name")
            .accessibilityInputLabels(["What are you focusing on", "Session name"])
    }

    // MARK: Controls

    private var controls: some View {
        let idle = engine.stage == .idle
        let undoable = idle && engine.undoableCancel != nil
        return VStack(spacing: Space.s) {
            primaryButton
            ZStack {
                secondaryRow
                // Laid out in every stage, shown only when idle, so the slot
                // keeps its height on Start and Cancel even when the hint wraps.
                // At the largest text sizes it can run to several lines,
                // so then it only takes space when it shows.
                if idle || !dynamicTypeSize.isAccessibilitySize {
                    AlertHint(status: services.alertStatus)
                        .opacity(idle && !undoable ? 1 : 0)
                        .allowsHitTesting(idle && !undoable)
                        .accessibilityHidden(!idle || undoable)
                }
                // Takes Cancel's place for a few seconds, right under the finger,
                // arriving like the undo bar in History.
                if undoable {
                    UndoBar(message: String(localized: "Session cancelled"),
                            hint: String(localized: "Brings the session back"), undo: engine.undoCancel)
                        .transition(.bar(reduceMotion))
                }
            }
            .animation(Motion.calm(reduceMotion), value: undoable)
        }
    }

    private var primaryButton: some View {
        let (title, symbol, action) = primaryAction
        return Button(action: action) {
            Label {
                Text(title).contentTransition(.interpolate)
            } icon: {
                Image(systemName: symbol).contentTransition(.symbolEffect(.replace))
            }
            .font(.retro(.button))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .tint(buttonTint)
        .animation(Motion.tint(reduceMotion), value: engine.stage)
    }

    private var buttonTint: Color {
        switch engine.stage {
        case .idle: Retro.orange
        case .active(let session): Retro.tint(for: session.phase)
        case .focusComplete: Retro.avocado
        }
    }

    private var primaryAction: (String, String, () -> Void) {
        switch engine.stage {
        case .idle:
            (String(localized: "Start focus"), "play.fill", start)
        case .active(let session):
            session.isPaused
                ? (String(localized: "Resume"), "play.fill", engine.resume)
                : (String(localized: "Pause"), "pause.fill", engine.pause)
        case .focusComplete(let focus):
            (Copy.startBreak(seconds: engine.breakLength(after: focus)), "cup.and.saucer.fill", engine.startBreak)
        }
    }

    /// Quiet text buttons under the primary action. Always the same height
    /// so the layout doesn't jump between states.
    @ViewBuilder
    private var secondaryRow: some View {
        if case .active(let session) = engine.stage, session.phase == .focus {
            // Redraws only when Finish now unlocks.
            let schedule = TickSchedule(wakeDates: engine.controlChanges(after: .now))
            TimelineView(schedule) { context in
                let canFinish = engine.canFinishEarly(at: context.date)
                // Side by side, or stacked when large text won't fit them.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: Space.l))
                layout {
                    quietButton(String(localized: "Cancel session"), role: .destructive, action: engine.cancel)
                    quietButton(Copy.finishNow, action: engine.finishEarly)
                        .disabled(!canFinish)
                        .opacity(canFinish ? 1 : 0.45)
                        .accessibilityHint(String(localized: "Ends the session and keeps the minutes"))
                }
            }
            .id(schedule)
        } else {
            let action = secondaryAction
            quietButton(action.title ?? " ", role: action.role) { action.run?() }
                .opacity(action.title == nil ? 0 : 1)
                .disabled(action.title == nil)
                .accessibilityHidden(action.title == nil)
        }
    }

    private func quietButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            // The frame sits inside the label so the whole 44 pt row takes the tap.
            Text(title)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .font(.retro(.body))
        // Rust says it throws something away; everything else stays quiet.
        .foregroundStyle(role == .destructive ? Retro.rustText : Retro.inkSoft)
        .buttonStyle(.borderless)
    }

    private var secondaryAction: (title: String?, role: ButtonRole?, run: (() -> Void)?) {
        switch engine.stage {
        case .idle:
            (nil, nil, nil)
        case .active:
            (String(localized: "Skip break"), nil, engine.skipBreak)
        case .focusComplete:
            // Moving on without a break isn't skipping anything that started.
            (String(localized: "Done for now"), nil, engine.skipBreak)
        }
    }

    private func start() {
        nameFocused = false
        engine.start(name: sessionName)
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(AppServices.preview)
        .environment(AppServices.preview.engine)
        .modelContainer(AppServices.preview.container)
}
#endif
