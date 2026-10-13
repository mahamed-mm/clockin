import Foundation
import Testing
import UIKit
@testable import Clockin

@MainActor
final class SpyOrientation: OrientationRequesting {
    var calls: [(mask: UIInterfaceOrientationMask, turn: UIInterfaceOrientationMask?)] = []
    func allow(_ mask: UIInterfaceOrientationMask, turningTo orientation: UIInterfaceOrientationMask?) {
        calls.append((mask, orientation))
    }
}

/// When the session shows as a bedside clock, and what it does to the screen.
@MainActor
struct BedsideTests {
    let orientation = SpyOrientation()
    let running = ActiveSession(id: UUID(), name: "Essay", phase: .focus, plannedDuration: 1_500,
                                focusStartedAt: .now, state: .running(endDate: .now.addingTimeInterval(1_500)))

    func makeController() -> BedsideController { BedsideController(orientation: orientation) }

    @Test func turningThePhoneShowsItDuringASessionOnly() {
        let bedside = makeController()
        #expect(bedside.shows(running, onItsSide: true))
        #expect(!bedside.shows(running, onItsSide: false))
        #expect(!bedside.shows(nil, onItsSide: true))
    }

    @Test func theMoonButtonShowsItAndTurnsTheScreenEvenWithOrientationLock() throws {
        let bedside = makeController()
        bedside.enter()
        #expect(bedside.shows(running, onItsSide: false))
        let call = try #require(orientation.calls.last)
        #expect(call.mask == .landscape)
        #expect(call.turn == .landscapeRight)
    }

    @Test func leavingAfterTheButtonTurnsItBackUpright() throws {
        let bedside = makeController()
        bedside.enter()
        bedside.leave(onItsSide: true)
        #expect(!bedside.isChosen)
        let call = try #require(orientation.calls.last)
        #expect(call.mask == .allButUpsideDown)
        #expect(call.turn == .portrait)
    }

    @Test func leavingWhileSidewaysDoesntBounceStraightBack() {
        let bedside = makeController()
        bedside.leave(onItsSide: true)
        #expect(!bedside.shows(running, onItsSide: true))
        // Only the button turned the screen, so nothing is turned now.
        #expect(orientation.calls.last?.turn == nil)

        bedside.orientationChanged(onItsSide: false)
        #expect(bedside.shows(running, onItsSide: true))
    }

    @Test func aNewSessionStartsFresh() {
        let bedside = makeController()
        bedside.sessionChanged(to: running)
        bedside.leave(onItsSide: true)
        var next = running
        next.id = UUID()
        bedside.sessionChanged(to: next)
        #expect(bedside.shows(next, onItsSide: true))
    }

    @Test func theEndOfAPhaseEndsAChosenBedside() throws {
        let bedside = makeController()
        bedside.sessionChanged(to: running)
        bedside.enter()
        bedside.sessionChanged(to: nil)
        #expect(!bedside.isChosen)
        #expect(try #require(orientation.calls.last).turn == .portrait)
    }

    @Test func withSidewaysOffOnlySettingsShowsIt() {
        let bedside = makeController()
        #expect(!bedside.shows(running, onItsSide: true, followsRotation: false))
        bedside.enter()
        #expect(bedside.shows(running, onItsSide: false, followsRotation: false))
    }

    @Test func theScreenStaysOnOnlyWhileTheClockRuns() {
        var paused = running
        paused.state = .paused(remaining: 600)
        #expect(BedsideController.keepsScreenOn(showing: true, session: running))
        #expect(!BedsideController.keepsScreenOn(showing: true, session: paused))
        #expect(!BedsideController.keepsScreenOn(showing: false, session: running))
        #expect(!BedsideController.keepsScreenOn(showing: true, session: nil))
    }
}
