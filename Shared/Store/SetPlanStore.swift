import Foundation

protocol SetPlanStoring {
    func load() -> SetPlan?
    func save(_ plan: SetPlan?)
}

/// Today's plan as JSON in the App Group's defaults, beside the symbols, so
/// the widget could read it. Never in a backup: it's only for today.
struct DefaultsSetPlanStore: SetPlanStoring {
    var defaults: UserDefaults = SharedStore.defaults
    var key = "plan.v1"

    func load() -> SetPlan? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(SetPlan.self, from: data)
        } catch {
            Log.store.error("Unreadable plan; starting without one: \(error, privacy: .public)")
            return nil
        }
    }

    func save(_ plan: SetPlan?) {
        guard let plan else { return defaults.removeObject(forKey: key) }
        do {
            defaults.set(try JSONEncoder().encode(plan), forKey: key)
        } catch {
            Log.store.error("Couldn't save the plan: \(error, privacy: .public)")
        }
    }
}

final class InMemorySetPlanStore: SetPlanStoring {
    var plan: SetPlan?

    init(_ plan: SetPlan? = nil) {
        self.plan = plan
    }

    func load() -> SetPlan? { plan }
    func save(_ plan: SetPlan?) { self.plan = plan }
}
