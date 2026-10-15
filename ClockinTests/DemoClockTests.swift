import Foundation
import Testing
@testable import Clockin

/// `-DemoNow`: a time of day for screenshots, and nothing without it.
struct DemoClockTests {
    /// A Wednesday at 23:10 in Oslo.
    let lateEvening = Date(timeIntervalSince1970: 1_792_012_200)

    @Test func itIsInactiveWithoutTheArgument() {
        #expect(UserDefaults.standard.string(forKey: DemoClock.argumentKey) == nil)
        #expect(SharedStore.defaults.object(forKey: DemoClock.defaultsKey) == nil)
        #expect(DemoClock.offset == 0)
        #expect(TimeFormat.demoShift == 0)
        let now = Date.now
        #expect(TimeFormat.shown(now) == now)
        #expect(TickPose.hour(at: now, calendar: osloCalendar) == osloCalendar.component(.hour, from: now))
    }

    @Test func itParsesTodayAtThatTime() throws {
        let earlier = try #require(DemoClock.parse("09:41", now: lateEvening, calendar: osloCalendar))
        let shown = lateEvening.addingTimeInterval(earlier)
        #expect(osloCalendar.isDate(shown, inSameDayAs: lateEvening))
        #expect(osloCalendar.dateComponents([.hour, .minute], from: shown) == DateComponents(hour: 9, minute: 41))

        let later = try #require(DemoClock.parse("23:45", now: lateEvening, calendar: osloCalendar))
        #expect(later == 35 * 60)
        #expect(DemoClock.parse("7:05", now: lateEvening, calendar: osloCalendar) != nil)
    }

    @Test(arguments: ["", "9", "09:4", "25:00", "09:60", "+9:41", "nine:41", "09:41:00"])
    func itIgnoresAnythingElse(_ value: String) {
        #expect(DemoClock.parse(value, now: lateEvening, calendar: osloCalendar) == nil)
    }

    @Test func prepareKeepsOrClearsTheOffset() throws {
        let suite = "DemoClockTests.\(UUID().uuidString)"
        let arguments = try #require(UserDefaults(suiteName: suite + ".arguments"))
        let store = try #require(UserDefaults(suiteName: suite))
        defer {
            arguments.removePersistentDomain(forName: suite + ".arguments")
            store.removePersistentDomain(forName: suite)
        }
        arguments.set("09:41", forKey: DemoClock.argumentKey)
        DemoClock.prepare(arguments: arguments, store: store, now: lateEvening, calendar: osloCalendar)
        #expect(store.double(forKey: DemoClock.defaultsKey) == -(13 * 3600 + 29 * 60))

        arguments.removeObject(forKey: DemoClock.argumentKey)
        DemoClock.prepare(arguments: arguments, store: store, now: lateEvening, calendar: osloCalendar)
        #expect(store.object(forKey: DemoClock.defaultsKey) == nil)
    }

    @Test func aShiftWakesTickInTheMorning() throws {
        let shift = try #require(DemoClock.parse("09:41", now: lateEvening, calendar: osloCalendar))
        #expect(TickPose.hour(at: lateEvening, calendar: osloCalendar, shift: 0) == 23)
        #expect(TickPose.hour(at: lateEvening, calendar: osloCalendar, shift: shift) == 9)
        #expect(TickPose.forHistory(.idle, fullToday: 0,
                                    hour: TickPose.hour(at: lateEvening, calendar: osloCalendar, shift: shift)) == .ready)
    }

    @Test func nightChangesComeBackInRealTime() {
        let unshifted = TickPose.nightChanges(after: lateEvening, calendar: osloCalendar, shift: 0)
        #expect(unshifted.map { osloCalendar.component(.hour, from: $0) } == [22, 6])
        #expect(unshifted.allSatisfy { $0 > lateEvening })

        // Shown as 09:41, night starts at 22:00 shown: 12 h 19 min of real time from now.
        let shift = DemoClock.parse("09:41", now: lateEvening, calendar: osloCalendar) ?? 0
        let shifted = TickPose.nightChanges(after: lateEvening, calendar: osloCalendar, shift: shift)
        #expect(shifted.first?.timeIntervalSince(lateEvening) == TimeInterval(12 * 3600 + 19 * 60))
    }
}
