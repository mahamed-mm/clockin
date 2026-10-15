import SwiftData
import SwiftUI

struct FocusView: View {
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("lastSessionName") private var sessionName = ""
    @AppStorage(Onboarding.dialHintKey) private var dialHintSeen = false
    @AppStorage(Onboarding.welcomeKey) private var welcomeSeen = false
    /// At most two saved sessions: enough to tell a first launch and a first finish.
    @Query(Onboarding.firstSessions) private var firstSessions: [FocusRecord]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @FocusState private var nameFocused: Bool
    @State private var pickingSymbol = false
    /// The last tap or scroll, which the screen waits on before stepping back.
    @State private var lastTouch = Date.now
    @State private var steppedBack = false
    /// A parked thought on its way to Tick, from and to in global space.
    @State private var flight: (id: Int, from: CGPoint, to: CGPoint)?
    @State private var flightProgress = 0.0
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

    /// Screenshots with `-DemoData` leave out the simulator's alert warnings.
    private var hidesAlertHint: Bool {
        #if DEBUG
        DemoData.isRequested
        #else
        false
        #endif
    }

    private var savedSessions: Int { firstSessions.count + engine.pendingRecords.count }

    private var teachesDial: Bool {
        Onboarding.showsDialHint(seen: dialHintSeen, savedSessions: savedSessions, stage: engine.stage)
    }

    private var welcomes: Bool {
        Onboarding.showsWelcome(seen: welcomeSeen, savedSessions: savedSessions, stage: engine.stage)
    }

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
                    .safeAreaInset(edge: .bottom) {
                        if services.parkFieldOpen, engine.active?.phase == .focus {
                            ParkField(park: parkFromField) { services.parkFieldOpen = false }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .overlay { slipInFlight }
            }
        }
        .animation(Motion.calm(reduceMotion), value: services.parkFieldOpen)
        .onChange(of: engine.active?.phase) { _, phase in
            if phase != .focus { services.parkFieldOpen = false }
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
        .onChange(of: engine.stage) { old, new in
            touched()
            // Each first-launch hint goes once its moment has passed.
            if case .idle = old, new != .idle { dialHintSeen = true }
            if case .focusComplete = old, new.completedFocus == nil { welcomeSeen = true }
        }
        .onChange(of: services.settings.length) {
            dialHintSeen = true
            // Choosing a length is setting up the next session already.
            engine.dismissBreakOver()
        }
        .onChange(of: engine.breakOver?.endedAt, initial: true) {
            // Break's over: the next session is the last one again.
            if let name = engine.breakOver?.name, !name.isEmpty { sessionName = name }
        }
        .task(id: engine.breakOverEnds) {
            // Ten minutes on, or at midnight, it goes back to plain waiting.
            guard let ends = engine.breakOverEnds else { return }
            try? await Task.sleep(for: .seconds(max(0, ends.timeIntervalSinceNow) + 0.1))
            if !Task.isCancelled { engine.reconcile() }
        }
        .task(id: stepBackWindow) { await stepBack(during: stepBackWindow) }
    }

    // MARK: Parking a thought

    /// Parks the line, then, once the keyboard has gone and the dial has
    /// grown back, sends a slip from where the field was to Tick, who
    /// catches it. With Reduce Motion or Low Power Mode the slip just fades
    /// where it is and Tick stays still.
    private func parkFromField(_ text: String, from field: CGRect) {
        guard services.parkFromField(text) else { return }
        touched()
        let still = reduceMotion || services.power.isConstrained
        let id = (flight?.id ?? 0) + 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))
            let tick = services.tickFrame
            let from = CGPoint(x: field.minX + 40, y: field.midY)
            let flies = !still && tick != .zero
            let to = flies ? CGPoint(x: tick.midX, y: tick.minY + tick.height * 0.3) : from
            if flies { services.catchThought(at: Date.now.addingTimeInterval(TickCatch.flight)) }
            flight = (id, from, to)
            flightProgress = 0
            withAnimation(flies ? .timingCurve(0.3, 0, 0.4, 1, duration: TickCatch.flight) : .easeOut(duration: 0.4)) {
                flightProgress = 1
            } completion: {
                if flight?.id == id { flight = nil }
            }
        }
    }

    @ViewBuilder
    private var slipInFlight: some View {
        if let flight {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                ParkedSlip()
                    .modifier(SlipFlight(from: CGPoint(x: flight.from.x - origin.x, y: flight.from.y - origin.y),
                                         to: CGPoint(x: flight.to.x - origin.x, y: flight.to.y - origin.y),
                                         progress: flightProgress))
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: Stepping back

    private var stepBackWindow: DateInterval? {
        StepBack.window(for: engine.active, lastTouch: lastTouch, assistive: voiceOver || switchControl)
    }

    /// Everything round the dial, faded while the screen has stepped back.
    private var chromeOpacity: Double { steppedBack ? StepBack.opacity : 1 }

    private func touched() {
        lastTouch = .now
    }

    /// Comes forward at once, then fades back for `window`, if there is one.
    private func stepBack(during window: DateInterval?) async {
        if steppedBack {
            withAnimation(Motion.stepBack(reduceMotion, returning: true)) { steppedBack = false }
        }
        guard let window else { return }
        do {
            try await Task.sleep(for: .seconds(max(0, window.start.timeIntervalSinceNow)))
            withAnimation(Motion.stepBack(reduceMotion, returning: false)) { steppedBack = true }
            try await Task.sleep(for: .seconds(max(0, window.end.timeIntervalSinceNow)))
            withAnimation(Motion.stepBack(reduceMotion, returning: true)) { steppedBack = false }
        } catch {
            // Cancelled: a touch or a new stage starts over.
        }
    }

    private var standardLayout: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 640 || geo.size.width > geo.size.height * 1.15
            ZStack {
                PaperBackground(wash: wash)
                    .paperGrain()
                    .animation(Motion.tint(reduceMotion), value: engine.stage)
                    .animation(Motion.tint(reduceMotion), value: engine.breakOver)
                    .onTapGesture { nameFocused = false }
                if wide {
                    HStack(spacing: Space.xxl) {
                        flexibleDial
                            .padding(.vertical, Space.l)
                        ScrollView {
                            VStack(alignment: .leading, spacing: Space.l) {
                                FocusHeader(stage: engine.stage)
                                    .opacity(chromeOpacity)
                                sessionSlot
                                    .opacity(chromeOpacity)
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
            // Any tap counts, including ones a button takes.
            .simultaneousGesture(TapGesture().onEnded { touched() })
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
                    .fixedSize(horizontal: false, vertical: true)
                    .measuredHeight($headerHeight)
                    .opacity(chromeOpacity)
                DialFace(stage: engine.stage, size: side, celebration: services.celebrations, teaches: teachesDial,
                         crown: tickCrown)
                    .frame(maxWidth: .infinity)
                sessionSlot
                    // Its natural height, whatever room the dial leaves: text
                    // that may shrink to fit would otherwise shrink as the dial
                    // grows, and the dial and the slot would resize each other
                    // forever.
                    .fixedSize(horizontal: false, vertical: true)
                    .measuredHeight($slotHeight)
                    .opacity(chromeOpacity)
                controls
                    .fixedSize(horizontal: false, vertical: true)
                    .measuredHeight($controlsHeight)
            }
            .padding(Self.margins)
            .frame(minHeight: viewport.height)
            .contentShape(.rect)
            .onTapGesture { nameFocused = false }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onScrollPhaseChange { _, phase in
            if phase.isScrolling { touched() }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
    }

    /// A soft colour wash at the top of the page for each phase.
    private var wash: Color? {
        switch engine.stage {
        // Back from a break, the focus colour comes back in.
        case .idle: engine.breakOver == nil ? nil : Retro.orange
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
                     celebration: services.celebrations, teaches: teachesDial, crown: tickCrown)
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
                    if teachesDial {
                        Text(Copy.dragToSet)
                            .font(.retro(.meta))
                            .foregroundStyle(Retro.inkSoft)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    LengthChips()
                    nameField
                        .glassEffectID("session", in: glass)
                        .glassEffectTransition(.matchedGeometry)
                    RecentNames(typed: sessionName) { sessionName = $0 }
                    if !services.thoughts.unfiled.isEmpty {
                        ParkedList(thoughts: services.thoughts.unfiled, title: Copy.parkedEarlier,
                                   toggle: toggleThought, clear: services.clearUnfiledThoughts)
                            .padding(.top, Space.xs)
                            .transition(.opacity)
                    }
                }
            case .active(let session):
                VStack(spacing: Space.s) {
                    SessionChip(session: session)
                        .glassEffectID("session", in: glass)
                        .glassEffectTransition(.matchedGeometry)
                    if session.phase == .rest {
                        BreakStyleChips(session: session)
                            .transition(.opacity)
                        thoughtsAfterFocus
                    }
                }
            case .focusComplete(let focus):
                VStack(spacing: Space.xs) {
                    CompletionSummary(focus: focus, day: services.today)
                    OvertimeChip(focus: focus)
                    thoughtsAfterFocus
                    if welcomes {
                        WelcomeLine()
                            .padding(.top, Space.xs)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    /// What was parked during the focus session just done, at the
    /// completion screen and through the break.
    @ViewBuilder
    private var thoughtsAfterFocus: some View {
        if let after = services.thoughtsAfterFocus, !after.thoughts.isEmpty {
            ParkedList(thoughts: after.thoughts, toggle: toggleThought) {
                services.clearThoughts(of: after.session)
            }
            .padding(.top, Space.xs)
            .transition(.opacity)
        }
    }

    private func toggleThought(_ thought: ParkedThought) {
        services.setThoughtDone(thought.done != true, thought.id)
    }

    private var nameField: some View {
        HStack(spacing: Space.xxs) {
            nameSymbol
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
                .accessibilityLabel("Session name")
                .accessibilityInputLabels(["What are you focusing on", "Session name"])
        }
        .padding(.leading, Space.xxs)
        .padding(.trailing, Space.l)
        .padding(.vertical, 5)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// The name's symbol, swapping as a known name is typed. Tapped, it
    /// picks a symbol for the name; an unnamed session keeps the book.
    private var nameSymbol: some View {
        let symbol = services.symbol(for: sessionName)
        let named = !SymbolBook.key(for: sessionName).isEmpty
        return Button { pickingSymbol = true } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Retro.inkSoft)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .animation(Motion.snappy(reduceMotion), value: symbol)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!named)
        .accessibilityHidden(!named)
        .accessibilityLabel(Copy.changeSymbol)
        .accessibilityValue(Copy.symbolName(symbol))
        .popover(isPresented: $pickingSymbol) {
            SymbolPicker(name: sessionName, selected: symbol) { picked in
                services.setSymbol(picked, for: sessionName)
                pickingSymbol = false
            }
        }
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
                if (idle || !dynamicTypeSize.isAccessibilitySize) && !hidesAlertHint {
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
            .opacity(chromeOpacity)
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

    /// Tick's crown is the start button: it does what the big button does.
    private var tickCrown: (label: String, action: () -> Void) {
        let (label, _, action) = primaryAction
        return (label, action)
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
            LiveTimeline(schedule) { context in
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
