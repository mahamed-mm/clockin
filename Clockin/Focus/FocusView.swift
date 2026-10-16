import SwiftData
import SwiftUI
import TipKit

struct FocusView: View {
    @Environment(SessionEngine.self) private var engine
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
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
    /// The finished session's parked thoughts, opened from their folded row.
    @State private var parkedOpen = false
    /// The plan sheet is open.
    @State private var planning = false
    /// A planned name moving from its chip into the name field, and whether it's there yet.
    @State private var movingSlot: SetPlan.Slot?
    @State private var moveLanded = false
    /// Where the plan's chips and the field's text are, in global space, for the move.
    @State private var chipFrames: [UUID: CGRect] = [:]
    @State private var fieldTextFrame: CGRect = .zero
    /// The field's text, hidden while a planned name moves in, faded in with Reduce Motion.
    @State private var fieldTextShown = true
    /// The idle screen's hints, one at a time.
    @State private var idleTips = TipGroup(.ordered) {
        CrownTip()
        SymbolTip()
    }
    private let breakTip = BreakChipsTip()
    private let parkTip = ParkTip()
    /// When the typed name last got a new symbol, for Tick's nod.
    @State private var symbolNodAt: Date?
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
    /// The scroll view's own size as last measured. While the park field is
    /// open the page keeps laying out to the size from before (`viewport`).
    @State private var measuredViewport: CGSize = .zero
    @State private var viewportHeld = false
    @State private var scroll = ScrollPosition()
    /// How far the page is scrolled and how tall it is, for where a parked
    /// thought lands once the keyboard has gone.
    @State private var scrolled: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    /// The whole window, in global space: a slip only flies to a Tick inside it.
    @State private var window: CGRect = .zero
    /// The foot of the chips under the name field, in the page: kept above
    /// the keyboard while a name is typed, so the recent names can be reached.
    @State private var nameRowBottom: CGFloat = 0
    /// How far the page went down for them, to come back up by once the name's done.
    @State private var nameScroll: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var slotHeight: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0
    /// The smallest the dial gets before the page scrolls instead; grows with text size.
    @ScaledMetric(relativeTo: .body) private var dialMinimum: CGFloat = 160
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
        screen
            // An empty field takes up the plan whenever the screen comes back to it.
            .onAppear(perform: pickUpPlan)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { pickUpPlan() }
            }
            .onChange(of: services.todaysSet) { pickUpPlan() }
    }

    private var screen: some View {
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
                    .overlay { nameInFlight }
            }
        }
        .animation(Motion.calm(reduceMotion), value: services.parkFieldOpen)
        .onChange(of: engine.active?.phase) { _, phase in
            if phase != .focus { services.parkFieldOpen = false }
        }
        .task(id: services.parkFieldOpen) {
            // Closed: once the keyboard has had time to go, the page lays
            // out to what it measures again, in case it never came all the way back.
            guard !services.parkFieldOpen, viewportHeld else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, viewportHeld else { return }
            viewport = measuredViewport
            viewportHeld = false
        }
        .background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { window = $0 }
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
            if new == .idle {
                pickUpPlan()
                showHandoff()
            }
            // A new stage starts with the parked thoughts folded again.
            if old.completedFocus?.id != new.completedFocus?.id { parkedOpen = false }
            // Each first-launch hint goes once its moment has passed.
            if case .idle = old, new != .idle { dialHintSeen = true }
            if case .focusComplete = old, new.completedFocus == nil { welcomeSeen = true }
        }
        .sheet(isPresented: $planning) {
            PlanSheet(day: services.today, initial: services.todaysSet, save: savePlan)
                .fittedSheet()
        }
        .onChange(of: services.settings.length) {
            dialHintSeen = true
            // Choosing a length is setting up the next session already.
            engine.dismissBreakOver()
        }
        .onChange(of: engine.breakOver?.endedAt, initial: true) {
            // Break's over: the next planned session, or the last one again.
            if let name = engine.breakOver?.name, !name.isEmpty { sessionName = services.nextName(after: name) }
        }
        .task(id: engine.breakOverEnds) {
            // Ten minutes on, or at midnight, it goes back to plain waiting.
            guard let ends = engine.breakOverEnds else { return }
            try? await Task.sleep(for: .seconds(max(0, ends.timeIntervalSinceNow) + 0.1))
            if !Task.isCancelled { engine.reconcile() }
        }
        .task(id: stepBackWindow) { await stepBack(during: stepBackWindow) }
        .onChange(of: nameFocused) { _, focused in nameFocusChanged(focused) }
        .environment(\.tickWatchesName, nameFocused)
        .environment(\.tickNodAt, symbolNodAt)
        .onChange(of: services.symbol(for: sessionName)) { old, new in
            // A name that finds its symbol as it's typed: Tick approves.
            if nameFocused, new != SymbolCatalog.unnamed, new != old { symbolNodAt = .now }
        }
    }

    // MARK: Parking a thought

    /// Parks the line and sends a slip from where the field was straight to
    /// Tick, who catches it. The dial kept its size while the field was
    /// open, so the slip aims for where Tick will be once the page has
    /// scrolled back. With Reduce Motion or Low Power Mode, or with Tick
    /// out of sight, the slip just fades where it is and Tick stays still.
    private func parkFromField(_ text: String, from field: CGRect) {
        guard services.parkFromField(text) else { return }
        touched()
        let still = reduceMotion || services.power.isConstrained
        let id = (flight?.id ?? 0) + 1
        let from = CGPoint(x: field.minX + 40, y: field.midY)
        let unwind = FocusLayout.scrollUnwind(scrolled: scrolled, contentHeight: contentHeight,
                                              viewportHeight: viewport.height)
        let landing = still ? nil : FocusLayout.slipLanding(tick: services.tickFrame, unwind: unwind, window: window)
        if landing != nil { services.catchThought(at: Date.now.addingTimeInterval(TickCatch.flight)) }
        flight = (id, from, landing ?? from)
        flightProgress = 0
        withAnimation(landing != nil ? .timingCurve(0.3, 0, 0.4, 1, duration: TickCatch.flight) : .easeOut(duration: 0.4)) {
            flightProgress = 1
        } completion: {
            if flight?.id == id { flight = nil }
        }
    }

    /// The park field is open over a focus session.
    private var parking: Bool { services.parkFieldOpen && engine.active?.phase == .focus }

    /// A new size from the scroll view: laid out to, unless the park field
    /// holds the page, which then scrolls just enough to keep Tick in sight.
    private func measure(_ size: CGSize) {
        measuredViewport = size
        let laidOut = FocusLayout.layoutViewport(measured: size, current: viewport, held: viewportHeld,
                                                 fieldOpen: parking)
        viewport = laidOut.size
        viewportHeld = laidOut.held
        if parking, laidOut.held {
            // The dial's foot, with Tick's feet, just above the field.
            let foot = Self.margins.top + headerHeight + spacing + dialSide + Space.s
            let offset = FocusLayout.keepInSight(foot: foot, visibleHeight: size.height, scrolled: scrolled)
            if offset != scrolled { withAnimation(Motion.calm(reduceMotion)) { scroll.scrollTo(y: offset) } }
        } else if nameFocused, nameRowBottom > 0 {
            // The keyboard came up over the name: down just far enough for
            // the chips under it, never back up.
            let offset = FocusLayout.keepInSight(foot: nameRowBottom + Space.s, visibleHeight: size.height,
                                                 scrolled: scrolled)
            if offset > scrolled {
                nameScroll += offset - scrolled
                withAnimation(Motion.calm(reduceMotion)) { scroll.scrollTo(y: offset) }
            }
        }
    }

    /// The name's done: back up by what the keyboard took.
    private func nameFocusChanged(_ focused: Bool) {
        guard !focused, nameScroll > 0 else { return }
        let back = max(0, scrolled - nameScroll)
        nameScroll = 0
        withAnimation(Motion.calm(reduceMotion)) { scroll.scrollTo(y: back) }
    }

    /// The compact page's own coordinates, from the top of its content.
    private static let page = "focusPage"

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
            // Measured without the keyboard, so typing never turns the page on its side.
            let wide = FocusLayout.isWide(width: geo.size.width, height: geo.size.height + geo.safeAreaInsets.bottom)
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
                                FocusHeader(stage: engine.stage, nextName: sessionName)
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
    /// Between the header, dial, slot and controls: tighter on short screens.
    private var spacing: CGFloat { FocusLayout.spacing(viewportHeight: viewport.height) }

    /// The header steps aside while the park or name field has scrolled
    /// the page, rather than sit under the status bar.
    private var headerFaded: Bool {
        FocusLayout.headerFaded(keyboardField: parking || nameFocused, scrolled: scrolled)
    }

    /// The compact layout's dial: the height left over, within its bounds.
    private var dialSide: CGFloat {
        let chrome = headerHeight + slotHeight + controlsHeight + 3 * spacing
            + Self.margins.top + Self.margins.bottom
        return FocusLayout.dialSide(viewportHeight: viewport.height, chrome: chrome, minimum: dialMinimum,
                                    width: viewport.width - Self.margins.leading - Self.margins.trailing)
    }

    private var compactLayout: some View {
        let side = dialSide
        return ScrollView {
            VStack(spacing: spacing) {
                FocusHeader(stage: engine.stage, nextName: sessionName)
                    .fixedSize(horizontal: false, vertical: true)
                    .measuredHeight($headerHeight)
                    .opacity(headerFaded ? 0 : chromeOpacity)
                    .allowsHitTesting(!headerFaded)
                    .animation(Motion.calm(reduceMotion), value: headerFaded)
                DialFace(stage: engine.stage, size: side, celebration: services.celebrations, teaches: teachesDial,
                         crown: tickCrown)
                    .equatable()
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
            .coordinateSpace(.named(Self.page))
            .frame(minHeight: viewport.height)
            .contentShape(.rect)
            .onTapGesture { nameFocused = false }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollPosition($scroll)
        // While a thought is being typed, a drag can't take the keyboard
        // (and the half-typed line) away.
        .scrollDismissesKeyboard(parking ? .never : .interactively)
        .onScrollPhaseChange { _, phase in
            if phase.isScrolling { touched() }
        }
        .onScrollGeometryChange(for: [CGFloat].self) { geometry in
            [geometry.contentOffset.y + geometry.contentInsets.top, geometry.contentSize.height]
        } action: { _, metrics in
            scrolled = metrics[0]
            contentHeight = metrics[1]
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { measure($0) }
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
                .equatable()
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
                    Group {
                        if let plan = services.todaysSet {
                            PlanStrip(plan: plan, typed: sessionName, fieldFocused: nameFocused,
                                      report: { chipFrames[$0] = $1 }, pick: { moveIntoField($0) },
                                      pickRecent: { name in
                                          sessionName = name
                                          nameFocused = false
                                      },
                                      edit: { planning = true })
                                .transition(.opacity)
                        } else {
                            RecentNames(typed: sessionName, plan: { planning = true }) { sessionName = $0 }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.page)).maxY } action: {
                        nameRowBottom = $0
                    }
                    // Below the field, so the dial (and Tick on it) keeps its room.
                    if let tip = idleTips.currentTip {
                        TipView(tip)
                            .tipViewStyle(RetroTipStyle())
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
                        TipView(breakTip)
                            .tipViewStyle(RetroTipStyle())
                        thoughtsAfterFocus
                    }
                }
            case .focusComplete(let focus):
                VStack(spacing: Space.xs) {
                    CompletionSummary(focus: focus, day: services.today)
                    if parkedOpen {
                        OvertimeChip(focus: focus)
                        thoughtsAfterFocus
                    } else {
                        // Keep +N min and the folded thoughts side by side, stacked when they won't fit.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Space.xs) {
                                OvertimeChip(focus: focus)
                                thoughtsAfterFocus
                            }
                            VStack(spacing: Space.xs) {
                                OvertimeChip(focus: focus)
                                thoughtsAfterFocus
                            }
                        }
                    }
                    // One extra at a time: the first-session line, else a tip
                    // (never beside parked thoughts, and only with room for it).
                    if welcomes {
                        WelcomeLine()
                            .padding(.top, Space.xs)
                            .transition(.opacity)
                    } else if FocusLayout.roomForTip(viewportHeight: viewport.height) {
                        TipView(parkTip)
                            .tipViewStyle(RetroTipStyle())
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
            ParkedRow(thoughts: after.thoughts, toggle: toggleThought, clear: {
                services.clearThoughts(of: after.session)
            }, open: $parkedOpen)
            .transition(.opacity)
        }
    }

    // MARK: Today's plan

    /// A planned name on its way from its chip into the name field: placed
    /// on the chip's label, then moved by translation, growing to the
    /// field's size, so nothing is laid out again on the way.
    @ViewBuilder
    private var nameInFlight: some View {
        if let slot = movingSlot, let chip = chipFrames[slot.id], fieldTextFrame != .zero {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                // From the chip's name to the field's text.
                let from = CGPoint(x: chip.minX - origin.x, y: chip.midY - origin.y)
                let to = CGPoint(x: fieldTextFrame.minX - origin.x, y: fieldTextFrame.midY - origin.y)
                let height: CGFloat = 28
                PlanLabel(name: slot.name, symbol: services.symbol(for: slot.name), large: true, showsSymbol: false)
                    .fixedSize()
                    .frame(height: height, alignment: .leading)
                    .scaleEffect(moveLanded ? 1 : 0.88, anchor: .leading)
                    .offset(x: moveLanded ? to.x : from.x, y: (moveLanded ? to.y : from.y) - height / 2)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Puts a planned name in the field, moving it there from its chip after
    /// `delay`. Reduce Motion fades the field's text in instead; Low Power
    /// Mode just changes it.
    private func moveIntoField(_ slot: SetPlan.Slot, after delay: Double = 0) {
        services.planHandoff = nil
        sessionName = slot.name
        if services.power.isConstrained { return }
        fieldTextShown = false
        guard !reduceMotion else {
            withAnimation(Motion.calm(true).delay(delay)) { fieldTextShown = true }
            return
        }
        Task { @MainActor in
            // Once the screen has settled and the chip is laid out: the label
            // appears on the chip, then moves.
            try? await Task.sleep(for: .seconds(delay))
            movingSlot = slot
            moveLanded = false
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(Motion.calm(false)) {
                moveLanded = true
            } completion: {
                guard movingSlot?.id == slot.id else { return }
                movingSlot = nil
                withAnimation(Motion.snappy(false)) { fieldTextShown = true }
            }
        }
    }

    /// The plan sheet closed: with nothing in the field yet, the first
    /// planned name moves into it.
    private func savePlan(_ plan: SetPlan?) {
        services.editSet(plan)
        guard ActiveSession.cleanName(sessionName).isEmpty, engine.stage == .idle,
              let next = services.nextPlanned else { return }
        moveIntoField(next, after: 0.35 * Motion.speed)
    }

    private func pickUpPlan() {
        services.pickUpPlan(fieldFocused: nameFocused)
    }

    /// Back on the idle screen after a planned session: the next planned
    /// name, already in the field, moves in from the plan once the screen
    /// has settled. Not if the field has been changed since.
    private func showHandoff() {
        guard engine.stage == .idle, let id = services.planHandoff,
              let slot = services.todaysSet?.slots.first(where: { $0.id == id }) else { return }
        guard SymbolBook.key(for: sessionName) == SymbolBook.key(for: slot.name) else {
            services.planHandoff = nil
            return
        }
        moveIntoField(slot, after: 0.45 * Motion.speed)
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
                .opacity(fieldTextShown ? 1 : 0)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fieldTextFrame = $0 }
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
        let undo = idle ? engine.undoable.map(undoCopy) : nil
        let undoable = undo != nil
        return VStack(spacing: Space.s) {
            primaryButton
            ZStack {
                secondaryRow
                // Laid out in every stage, shown only when idle, so the slot
                // keeps its height on Start and Cancel even when the hint wraps.
                // At the largest text sizes it can run to several lines,
                // so then it only takes space when it shows.
                // Not after a session, where the room goes to the summary.
                if (idle || !(dynamicTypeSize.isAccessibilitySize || engine.stage.completedFocus != nil)) && !hidesAlertHint {
                    AlertHint(status: services.alertStatus)
                        .opacity(idle && !undoable ? 1 : 0)
                        .allowsHitTesting(idle && !undoable)
                        .accessibilityHidden(!idle || undoable)
                }
                // Takes the button's place for a few seconds, right under the
                // finger, arriving like the undo bar in History.
                if let undo {
                    UndoBar(message: undo.message, hint: undo.hint, undo: engine.undo)
                        .transition(.bar(reduceMotion))
                }
            }
            .animation(Motion.calm(reduceMotion), value: undoable)
            .opacity(chromeOpacity)
        }
    }

    private func undoCopy(_ undoable: SessionEngine.Undoable) -> (message: String, hint: String) {
        switch undoable {
        case .cancel:
            (String(localized: "Session cancelled"), String(localized: "Brings the session back"))
        case .skip:
            (String(localized: "Break skipped"), String(localized: "Brings the break back"))
        case .dismiss:
            (String(localized: "No break this time"), String(localized: "Brings the break offer back"))
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
        return (label, {
            ClockinTips.note(ClockinTips.crownTapped)
            action()
        })
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
        if engine.start(name: sessionName), !ActiveSession.cleanName(sessionName).isEmpty {
            ClockinTips.note(ClockinTips.namedSessionStarted)
        }
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
