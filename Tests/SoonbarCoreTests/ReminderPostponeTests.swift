import Foundation
import Testing
@testable import SoonbarCore

struct ReminderPostponeTests {
    let calendar = Fixture.calendar
    // Thursday 8 Oct 2026, 14:07.
    let now = Fixture.date(2026, 10, 8, 14, 7)

    @Test func inAnHourRoundsUpToFiveMinutes() {
        let due = ReminderPostpone.inAnHour.newDue(for: Fixture.reminder("Call", now), now: now, calendar: calendar)
        #expect(due.date == Fixture.date(2026, 10, 8, 15, 10))
        #expect(due.hasTime)
    }

    @Test func thisEveningIsSixPM() {
        let due = ReminderPostpone.thisEvening.newDue(for: Fixture.reminder("Call", now), now: now, calendar: calendar)
        #expect(due.date == Fixture.date(2026, 10, 8, 18, 0))
        #expect(due.hasTime)
    }

    @Test func thisEveningIsOfferedOnlyWhileAtLeastAnHourAway() {
        #expect(ReminderPostpone.options(now: now, calendar: calendar).contains(.thisEvening))
        #expect(ReminderPostpone.options(now: Fixture.date(2026, 10, 8, 16, 59), calendar: calendar).contains(.thisEvening))
        #expect(!ReminderPostpone.options(now: Fixture.date(2026, 10, 8, 17, 0), calendar: calendar).contains(.thisEvening))
        #expect(ReminderPostpone.options(now: Fixture.date(2026, 10, 8, 17, 0), calendar: calendar).count == 3)
    }

    @Test func tomorrowKeepsTheTimeOfDay() {
        let reminder = Fixture.reminder("Pay rent", Fixture.date(2026, 10, 8, 9, 30))
        let due = ReminderPostpone.tomorrow.newDue(for: reminder, now: now, calendar: calendar)
        #expect(due.date == Fixture.date(2026, 10, 9, 9, 30))
        #expect(due.hasTime)
    }

    @Test func dateOnlyRemindersStayDateOnly() {
        let reminder = Fixture.reminder("Pay rent", Fixture.date(2026, 10, 8), hasTime: false)
        let due = ReminderPostpone.tomorrow.newDue(for: reminder, now: now, calendar: calendar)
        #expect(due.date == Fixture.date(2026, 10, 9))
        #expect(!due.hasTime)
    }

    @Test func overdueRemindersMoveForwardFromToday() {
        let reminder = Fixture.reminder("Old", Fixture.date(2026, 9, 20, 11, 0))
        let due = ReminderPostpone.tomorrow.newDue(for: reminder, now: now, calendar: calendar)
        #expect(due.date == Fixture.date(2026, 10, 9, 11, 0))
    }

    @Test func nextWeekIsNextMonday() {
        let reminder = Fixture.reminder("Plan", Fixture.date(2026, 10, 8, 10, 0))
        #expect(ReminderPostpone.nextWeek.newDue(for: reminder, now: now, calendar: calendar).date == Fixture.date(2026, 10, 12, 10, 0))
        // On a Monday it means the following Monday, not today.
        let monday = Fixture.date(2026, 10, 12, 8, 0)
        #expect(ReminderPostpone.nextWeek.newDue(for: reminder, now: monday, calendar: calendar).date == Fixture.date(2026, 10, 19, 10, 0))
    }
}
