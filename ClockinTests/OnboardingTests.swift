import Foundation
import Testing
@testable import Clockin

/// First-launch teaching shows once, only to someone new.
struct OnboardingTests {
    let focus = CompletedFocus(id: UUID(), name: "", startedAt: .distantPast, completedAt: .distantPast,
                               focusSeconds: 1500)

    @Test func theGhostThumbIsForAFirstLaunchOnly() {
        #expect(Onboarding.showsDialHint(seen: false, savedSessions: 0, stage: .idle))
        #expect(!Onboarding.showsDialHint(seen: true, savedSessions: 0, stage: .idle))
        // Updating with History already there: never shown.
        #expect(!Onboarding.showsDialHint(seen: false, savedSessions: 1, stage: .idle))
        #expect(!Onboarding.showsDialHint(seen: false, savedSessions: 0, stage: .focusComplete(focus)))
    }

    @Test func theClosingLineFollowsTheFirstSessionOnly() {
        #expect(Onboarding.showsWelcome(seen: false, savedSessions: 1, stage: .focusComplete(focus)))
        #expect(!Onboarding.showsWelcome(seen: true, savedSessions: 1, stage: .focusComplete(focus)))
        #expect(!Onboarding.showsWelcome(seen: false, savedSessions: 2, stage: .focusComplete(focus)))
        #expect(!Onboarding.showsWelcome(seen: false, savedSessions: 1, stage: .idle))
    }

    @Test func copy() {
        #expect(Copy.dragToSet == "Drag the knob to set the time")
        #expect(Copy.wholeApp == "That's the whole app.")
    }
}
