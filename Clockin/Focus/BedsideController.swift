import SwiftUI
import UIKit

/// The orientations the app allows, read by the app delegate. Bedside mode
/// narrows it to landscape, which rotates the screen even with orientation
/// lock on.
@MainActor
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown
}

/// Changes what the screen may show and turns it. A seam so tests don't
/// need a window.
@MainActor
protocol OrientationRequesting {
    /// Allows only `mask`, then turns the screen to `orientation` if given.
    func allow(_ mask: UIInterfaceOrientationMask, turningTo orientation: UIInterfaceOrientationMask?)
}

struct SystemOrientation: OrientationRequesting {
    func allow(_ mask: UIInterfaceOrientationMask, turningTo orientation: UIInterfaceOrientationMask?) {
        OrientationLock.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        // The new mask first, or the system turns the request down against the old one.
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        guard let orientation else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
            Log.store.error("Couldn't turn the screen: \(error, privacy: .public)")
        }
    }
}

/// Whether the session shows as a bedside clock: chosen in Settings, or
/// when the phone is turned on its side (if Settings allows that).
@MainActor
@Observable
final class BedsideController {
    /// Chosen with "Show bedside clock", which also turns the screen.
    private(set) var isChosen = false
    /// Left while the phone was still on its side: don't jump straight back
    /// in until it's upright again or a new session starts.
    private(set) var isHeldOff = false
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private let orientation: OrientationRequesting

    init(orientation: OrientationRequesting = SystemOrientation()) {
        self.orientation = orientation
    }

    /// `followsRotation` is the "Turn sideways for the bedside clock" setting.
    func shows(_ session: ActiveSession?, onItsSide: Bool, followsRotation: Bool = true) -> Bool {
        guard session != nil else { return false }
        return isChosen || (followsRotation && onItsSide && !isHeldOff)
    }

    func enter() {
        isChosen = true
        isHeldOff = false
        orientation.allow(.landscape, turningTo: .landscapeRight)
    }

    func leave(onItsSide: Bool) {
        let wasChosen = isChosen
        isChosen = false
        isHeldOff = onItsSide
        // Turned upright only if it was chosen (and so turned); otherwise the phone decides.
        orientation.allow(.allButUpsideDown, turningTo: wasChosen ? .portrait : nil)
    }

    func orientationChanged(onItsSide: Bool) {
        if !onItsSide { isHeldOff = false }
    }

    /// When a phase ends, bedside ends with it; a new session starts fresh.
    func sessionChanged(to session: ActiveSession?) {
        if session?.id != sessionID {
            sessionID = session?.id
            isHeldOff = false
        }
        if session == nil, isChosen {
            isChosen = false
            orientation.allow(.allButUpsideDown, turningTo: .portrait)
        }
    }

    /// The screen stays on only while the clock is showing and running.
    static func keepsScreenOn(showing: Bool, session: ActiveSession?) -> Bool {
        showing && session.map { !$0.isPaused } == true
    }
}

/// Reports `OrientationLock` to the system.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.mask }
    }
}
