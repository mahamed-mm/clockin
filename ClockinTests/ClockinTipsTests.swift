import Foundation
import Testing
import TipKit
@testable import Clockin

/// The hints: one each, worded through Copy, waiting on the right moments.
@MainActor
struct ClockinTipsTests {
    @Test func everyTipIsItsOwn() {
        let tips: [any Tip] = [CrownTip(), SymbolTip(), HistoryTapTip(), HistoryMenuTip(), BreakChipsTip(), ParkTip()]
        #expect(Set(tips.map(\.id)).count == tips.count)
        #expect(tips.count == ClockinTips.all.count)
        for tip in tips { #expect(!tip.rules.isEmpty, "\(tip.id) waits on something") }
    }

    @Test func theWordsComeFromCopy() {
        for text in [Copy.tipCrownTitle, Copy.tipCrownMessage, Copy.tipSymbolTitle, Copy.tipSymbolMessage,
                     Copy.tipHistoryTapTitle, Copy.tipHistoryTapMessage, Copy.tipHistoryMenuTitle,
                     Copy.tipHistoryMenuMessage, Copy.tipBreakChipsTitle, Copy.tipBreakChipsMessage,
                     Copy.tipParkTitle, Copy.tipParkMessage] {
            #expect(!text.isEmpty)
            #expect(!text.contains("streak") && !text.contains("!"), "calm, nothing to earn: \(text)")
        }
    }

    /// No tip during focus or before the first finish; the services keep that up to date.
    @Test func focusAndFirstFinishAreKnown() {
        let clock = FakeClock()
        let services = AppServices(container: AppServices.makeEmptyContainer(),
                                   stateStore: InMemorySessionStateStore(), now: { [clock] in clock.now },
                                   calendar: osloCalendar, schedulesCompletion: false,
                                   liveActivity: SpyLiveActivity(), notifications: SpyNotifier(),
                                   widgets: SpyWidgets(), haptics: SpyHaptics(), announce: { _ in })
        services.engine.start(name: "Essay")
        #expect(ClockinTips.focusRunning)
        clock.advance(Preset.classic.focus)
        services.reconcile()
        #expect(!ClockinTips.focusRunning)
        #expect(ClockinTips.hasFinished)
        services.engine.startBreak()
        #expect(!ClockinTips.focusRunning, "a break isn't focus")
    }
}
