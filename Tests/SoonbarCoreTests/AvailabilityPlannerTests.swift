import Foundation
import Testing
@testable import SoonbarCore

@Suite struct AvailabilityPlannerTests {
    let cal = Fixture.calendar

    func settings(days: Int = 3, minimum: Int = 30, hours: WorkingHours = .standard) -> AvailabilitySettings {
        AvailabilitySettings(workingDays: days, workingHours: hours, minimumMinutes: minimum)
    }

    func hm(_ date: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    func dayKey(_ date: Date) -> String {
        let c = cal.dateComponents([.month, .day], from: date)
        return "\(c.month!)/\(c.day!)"
    }

    /// "9/29 10:15-18:00" per slot.
    func plan(_ events: [CalendarEvent], now: Date, _ settings: AvailabilitySettings) -> [String] {
        AvailabilityPlanner.days(events: events, now: now, settings: settings, calendar: cal).map { day in
            ([dayKey(day.day)] + day.slots.map { "\(hm($0.start))-\(hm($0.end))" }).joined(separator: " ")
        }
    }

    @Test func coversWorkingDaysAndSkipsTheWeekend() {
        let now = Fixture.date(2026, 10, 1, 10) // Thursday
        #expect(plan([], now: now, settings(days: 3)) == ["10/1 10:00-18:00", "10/2 09:00-18:00", "10/5 09:00-18:00"])
    }

    @Test func weekendStartsOnMonday() {
        let now = Fixture.date(2026, 10, 3, 11) // Saturday
        #expect(plan([], now: now, settings(days: 2)) == ["10/5 09:00-18:00", "10/6 09:00-18:00"])
    }

    @Test func todayStartsAtNowRoundedUpToTheQuarterHour() {
        #expect(plan([], now: Fixture.date(2026, 9, 29, 10, 7), settings(days: 1)) == ["9/29 10:15-18:00"])
        #expect(plan([], now: Fixture.date(2026, 9, 29, 10, 15), settings(days: 1)) == ["9/29 10:15-18:00"])
        #expect(plan([], now: Fixture.date(2026, 9, 29, 10, 46), settings(days: 1)) == ["9/29 11:00-18:00"])
    }

    @Test func beforeWorkTodayStartsAtWorkingHours() {
        #expect(plan([], now: Fixture.date(2026, 9, 29, 7, 20), settings(days: 1)) == ["9/29 09:00-18:00"])
    }

    @Test func todayIsSkippedOnceItsWorkingHoursAreOver() {
        // 17:50 rounds up to 18:00, when work ends.
        #expect(plan([], now: Fixture.date(2026, 9, 29, 17, 50), settings(days: 1)) == ["9/30 09:00-18:00"])
        #expect(plan([], now: Fixture.date(2026, 9, 29, 19), settings(days: 2)) == ["9/30 09:00-18:00", "10/1 09:00-18:00"])
    }

    @Test func busyTimeMergesAndShortGapsAreDropped() {
        let now = Fixture.date(2026, 9, 29, 8)
        let events = [
            Fixture.event("A", Fixture.date(2026, 9, 29, 10), Fixture.date(2026, 9, 29, 11, 30)),
            Fixture.event("B", Fixture.date(2026, 9, 29, 11), Fixture.date(2026, 9, 29, 12)),
            Fixture.event("C", Fixture.date(2026, 9, 29, 12, 20), Fixture.date(2026, 9, 29, 14)),
            Fixture.event("D", Fixture.date(2026, 9, 30, 9), Fixture.date(2026, 9, 30, 17)),
        ]
        #expect(plan(events, now: now, settings(days: 2)) == [
            "9/29 09:00-10:00 14:00-18:00",
            "9/30 17:00-18:00",
        ])
    }

    @Test func shortestSlotFollowsTheSetting() {
        let now = Fixture.date(2026, 9, 29, 8)
        let events = [
            Fixture.event("A", Fixture.date(2026, 9, 29, 9, 15), Fixture.date(2026, 9, 29, 12)),
            Fixture.event("B", Fixture.date(2026, 9, 29, 12, 45), Fixture.date(2026, 9, 29, 18)),
        ]
        #expect(plan(events, now: now, settings(days: 1, minimum: 15)) == ["9/29 09:00-09:15 12:00-12:45"])
        #expect(plan(events, now: now, settings(days: 1, minimum: 30)) == ["9/29 12:00-12:45"])
        #expect(plan(events, now: now, settings(days: 1, minimum: 60)) == ["9/29"])
    }

    @Test func declinedCancelledAndAllDayEventsAreNotBusy() {
        let now = Fixture.date(2026, 9, 29, 8)
        let events = [
            Fixture.event("Declined", Fixture.date(2026, 9, 29, 10), Fixture.date(2026, 9, 29, 11), declined: true),
            Fixture.event("Cancelled", Fixture.date(2026, 9, 29, 12), Fixture.date(2026, 9, 29, 13), cancelled: true),
            Fixture.event("Holiday", Fixture.date(2026, 9, 29), Fixture.date(2026, 9, 30), allDay: true),
        ]
        #expect(plan(events, now: now, settings(days: 1)) == ["9/29 09:00-18:00"])
    }

    @Test func eventsAcrossMidnightBlockBothDays() {
        let now = Fixture.date(2026, 9, 29, 8)
        let trip = Fixture.event("Trip", Fixture.date(2026, 9, 29, 16), Fixture.date(2026, 9, 30, 11))
        #expect(plan([trip], now: now, settings(days: 2)) == ["9/29 09:00-16:00", "9/30 11:00-18:00"])
    }

    @Test func fullyBookedDaysStillCount() {
        let now = Fixture.date(2026, 9, 29, 8)
        let busy = Fixture.event("Offsite", Fixture.date(2026, 9, 29, 9), Fixture.date(2026, 9, 29, 18))
        #expect(plan([busy], now: now, settings(days: 2)) == ["9/29", "9/30 09:00-18:00"])
    }

    @Test func freeAllDayOnlyWhenTheWholeWorkingDayIsOpen() {
        let days = AvailabilityPlanner.days(
            events: [], now: Fixture.date(2026, 9, 29, 10), settings: settings(days: 2), calendar: cal
        )
        #expect(days.map(\.isFreeAllDay) == [false, true])
    }

    @Test func workingHoursFollowTheWallClockAcrossDST() {
        let now = Fixture.date(2026, 10, 23, 8) // Friday; clocks go back on Sunday 25 Oct
        #expect(plan([], now: now, settings(days: 2)) == ["10/23 09:00-18:00", "10/26 09:00-18:00"])
    }

    @Test func customWorkingHours() {
        let hours = WorkingHours(startMinutes: 8 * 60 + 30, endMinutes: 24 * 60)
        #expect(plan([], now: Fixture.date(2026, 9, 29, 7), settings(days: 1, hours: hours)) == ["9/29 08:30-00:00"])
    }

    @Test func invalidWorkingHoursOfferNothing() {
        let hours = WorkingHours(startMinutes: 18 * 60, endMinutes: 9 * 60)
        #expect(plan([], now: Fixture.date(2026, 9, 29, 7), settings(days: 3, hours: hours)).isEmpty)
        #expect(AvailabilityPlanner.interval(now: Fixture.date(2026, 9, 29, 7), settings: settings(hours: hours), calendar: cal) == nil)
    }

    @Test func intervalRunsFromTodayToTheEndOfTheLastDay() {
        let interval = AvailabilityPlanner.interval(now: Fixture.date(2026, 10, 1, 10), settings: settings(days: 3), calendar: cal)
        #expect(interval == DateInterval(start: Fixture.date(2026, 10, 1), end: Fixture.date(2026, 10, 5, 18)))
    }

    @Test func roundsUpOnTheLocalWallClock() {
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let date = kolkata.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 10, minute: 7, second: 30))!
        let rounded = AvailabilityPlanner.roundedUp(date, toMinutes: 15, calendar: kolkata)
        #expect(kolkata.dateComponents([.hour, .minute, .second], from: rounded) == DateComponents(hour: 10, minute: 15, second: 0))
    }
}
