import Foundation
import Observation

/// Whether the phone is asking apps to go easy: Low Power Mode, or running
/// hot. Decorative animation stops and the dial's arc moves once a minute;
/// the countdown keeps ticking.
@MainActor
@Observable
final class PowerState {
    private(set) var isConstrained: Bool
    @ObservationIgnored private let read: @MainActor () -> Bool
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(read: @escaping @MainActor () -> Bool = PowerState.systemIsConstrained) {
        self.read = read
        isConstrained = read()
    }

    static func systemIsConstrained() -> Bool {
        let info = ProcessInfo.processInfo
        return isConstrained(lowPowerMode: info.isLowPowerModeEnabled, thermalState: info.thermalState)
    }

    nonisolated static func isConstrained(lowPowerMode: Bool, thermalState: ProcessInfo.ThermalState) -> Bool {
        lowPowerMode || thermalState == .serious || thermalState == .critical
    }

    /// Follows changes from now on. Both notifications can arrive on any thread.
    func observe() {
        let names: [Notification.Name] = [.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func refresh() {
        let constrained = read()
        if constrained != isConstrained { isConstrained = constrained }
    }
}
