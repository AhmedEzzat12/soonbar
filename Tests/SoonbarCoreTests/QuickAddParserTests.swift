import Foundation
import Testing
@testable import SoonbarCore

/// NSDataDetector resolves "tomorrow" against the real clock and the system time zone,
/// so these tests use Calendar.current and Date() rather than Fixture.
@Suite struct QuickAddParserTests {
    let cal = Calendar.current
    let calendars: [CalendarInfo] = [
        CalendarInfo(id: "work-stuff", title: "Work Stuff", color: .gray, accountID: "g", kind: .events, isWritable: true),
        CalendarInfo(id: "work", title: "Work", color: .gray, accountID: "g", kind: .events, isWritable: true),
        CalendarInfo(id: "family", title: "Family Plans", color: .gray, accountID: "i", kind: .events, isWritable: true),
        CalendarInfo(id: "holidays", title: "Holidays", color: .gray, accountID: "i", kind: .events, isWritable: false),
        CalendarInfo(id: "r-work", title: "Work", color: .gray, accountID: "g", kind: .reminders, isWritable: true),
    ]

    func parse(_ text: String, now: Date = Date(), forcedKind: QuickAddKind? = nil) -> QuickAddDraft {
        QuickAddParser(calendar: cal, now: now).parse(text, calendars: calendars, forcedKind: forcedKind)
    }

    func today(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func tomorrow(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: 1, to: Date())!)!
    }

    @Test func plainTitleStartsAtNextHalfHour() {
        let draft = parse("Focus block", now: today(10, 7))
        #expect(draft.kind == .event)
        #expect(draft.title == "Focus block")
        #expect(draft.start == today(10, 30))
        #expect(draft.end == today(11, 0))
        #expect(!draft.isAllDay)
        #expect(!draft.hasExplicitDate)
        #expect(draft.calendarID == nil)
    }

    @Test func halfHourRollsIntoNextHour() {
        #expect(parse("Focus", now: today(10, 30)).start == today(11, 0))
    }

    @Test(arguments: [
        ("Review for 45m", "Review", 45),
        ("Planning 1h30m", "Planning", 90),
        ("Deep work 1.5h", "Deep work", 90),
        ("Sync 2 hours", "Sync", 120),
        ("Chat 20 min", "Chat", 20),
    ])
    func durations(input: String, title: String, minutes: Int) {
        let draft = parse(input, now: today(10, 7))
        #expect(draft.title == title)
        #expect(draft.end.timeIntervalSince(draft.start) == TimeInterval(minutes * 60))
    }

    @Test func hashtagExactMatchBeatsPrefix() {
        let draft = parse("Standup #work")
        #expect(draft.calendarID == "work")
        #expect(draft.title == "Standup")
    }

    @Test func hashtagPrefixMatch() {
        #expect(parse("Dinner #fam").calendarID == "family")
    }

    @Test func hashtagSubstringMatch() {
        #expect(parse("Deploy #stuff").calendarID == "work-stuff")
    }

    @Test func readOnlyCalendarsAreNotTargets() {
        let draft = parse("Day off #holidays")
        #expect(draft.calendarID == nil)
        #expect(draft.unmatchedCalendarToken == "holidays")
    }

    @Test func unmatchedHashtagIsReported() {
        let draft = parse("Gym #zzz")
        #expect(draft.calendarID == nil)
        #expect(draft.unmatchedCalendarToken == "zzz")
        #expect(draft.title == "Gym")
    }

    @Test func bangMakesReminderInMatchingList() {
        let draft = parse("!Send report #work", now: today(10))
        #expect(draft.kind == .reminder)
        #expect(draft.calendarID == "r-work")
        #expect(draft.title == "Send report")
        #expect(!draft.hasDueTime)
        #expect(draft.start == cal.startOfDay(for: today(10)))
    }

    @Test func forcedKindOverridesBang() {
        #expect(parse("!Send report", forcedKind: .event).kind == .event)
    }

    @Test func tomorrowWithTimeAndDuration() {
        let draft = parse("Lunch with Sara tomorrow 1pm 1h #work")
        #expect(draft.title == "Lunch with Sara")
        #expect(draft.calendarID == "work")
        #expect(draft.start == tomorrow(13))
        #expect(draft.end == tomorrow(14))
        #expect(draft.hasExplicitDate)
    }

    @Test func dateWithoutTimeIsAllDay() {
        let draft = parse("Offsite tomorrow")
        #expect(draft.isAllDay)
        #expect(draft.title == "Offsite")
        #expect(draft.start == cal.startOfDay(for: tomorrow(12)))
        #expect(draft.end == cal.date(byAdding: .day, value: 1, to: draft.start))
    }

    @Test func reminderWithTime() {
        let draft = parse("!Call mom tomorrow at 6pm")
        #expect(draft.kind == .reminder)
        #expect(draft.hasDueTime)
        #expect(draft.start == tomorrow(18))
        #expect(draft.title == "Call mom")
    }

    @Test func timeRangeSetsEnd() {
        let draft = parse("Workshop tomorrow from 2pm to 4pm")
        #expect(draft.start == tomorrow(14))
        #expect(draft.end == tomorrow(16))
        #expect(draft.title == "Workshop")
    }

    @Test func detectorDoesNotSwallowTitleWords() {
        // NSDataDetector matches "Dinner friday 7pm" as one phrase.
        let draft = parse("Dinner friday 7pm")
        #expect(draft.title == "Dinner")
        #expect(cal.component(.weekday, from: draft.start) == 6)
        #expect(cal.component(.hour, from: draft.start) == 19)
    }

    @Test func emptyInputs() {
        #expect(parse("").title == "")
        let bang = parse("!")
        #expect(bang.kind == .reminder)
        #expect(bang.title == "")
    }
}

@Suite struct QuickAddDraftNormalizationTests {
    let cal = Fixture.calendar

    func draft(kind: QuickAddKind = .event, allDay: Bool, start: Date, end: Date) -> QuickAddDraft {
        QuickAddDraft(
            kind: kind, title: "T", calendarID: nil, unmatchedCalendarToken: nil, isAllDay: allDay,
            start: start, end: end, hasDueTime: false, hasExplicitDate: true
        )
    }

    @Test func allDayEventBecomesOneWholeDay() {
        // Start moved by the picker keeps a 25-hour "length" (DST fall-back) and a non-midnight time.
        let start = Fixture.date(2026, 10, 1, 10, 30)
        let normalized = draft(allDay: true, start: start, end: start.addingTimeInterval(25 * 3600)).normalized(calendar: cal)
        #expect(normalized.start == Fixture.date(2026, 10, 1))
        #expect(normalized.end == Fixture.date(2026, 10, 2))
    }

    @Test func timedEventsAndRemindersAreUntouched() {
        let start = Fixture.date(2026, 10, 1, 10, 30)
        let timed = draft(allDay: false, start: start, end: start.addingTimeInterval(1800))
        #expect(timed.normalized(calendar: cal) == timed)
        let reminder = draft(kind: .reminder, allDay: true, start: start, end: start)
        #expect(reminder.normalized(calendar: cal) == reminder)
    }

}

/// Phrases the system date detection misses.
extension QuickAddParserTests {

    /// The next date (today included) on `weekday` (1 = Sunday), at midnight.
    func upcoming(_ weekday: Int) -> Date {
        let start = cal.startOfDay(for: Date())
        return cal.nextDate(after: start.addingTimeInterval(-1), matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)!
    }

    var isWeekend: Bool { [1, 7].contains(cal.component(.weekday, from: Date())) }

    @Test func nextWeekdayKeepsNextOutOfTheTitle() {
        let draft = parse("Design review next Tuesday at 3pm")
        #expect(draft.title == "Design review")
        #expect(cal.component(.weekday, from: draft.start) == 3)
        #expect(cal.component(.hour, from: draft.start) == 15)
    }

    @Test func thisWeekdayKeepsThisOutOfTheTitle() {
        #expect(parse("Pay rent this Friday").title == "Pay rent")
    }

    @Test func bareHourAfterADayIsATime() {
        let draft = parse("Coffee tomorrow 11")
        #expect(draft.title == "Coffee")
        #expect(draft.start == tomorrow(11))
        #expect(!draft.isAllDay)
    }

    @Test func bareHourBeforeAJoiningWord() {
        let draft = parse("Meet tomorrow 11 for coffee")
        #expect(draft.start == tomorrow(11))
        #expect(draft.title == "Meet for coffee")
    }

    @Test func smallBareHoursMeanTheAfternoon() {
        #expect(parse("Call tomorrow 3").start == tomorrow(15))
        #expect(parse("Call tomorrow 12").start == tomorrow(12))
    }

    @Test func aNumberThatCountsSomethingStaysInTheTitle() {
        let draft = parse("Order tomorrow 12 boxes")
        #expect(draft.isAllDay)
        #expect(draft.title == "Order 12 boxes")
    }

    @Test func weekdayAndNumberIsAnHourNotAPastDate() {
        let draft = parse("Gym friday 9")
        #expect(draft.start >= cal.startOfDay(for: Date()))
        #expect(cal.component(.weekday, from: draft.start) == 6)
        #expect(cal.component(.hour, from: draft.start) == 9)
        #expect(draft.title == "Gym")
    }

    @Test func thisWeekIsDueFriday() {
        let draft = parse("!Renew domain this week")
        #expect(draft.kind == .reminder)
        #expect(draft.title == "Renew domain")
        #expect(!draft.hasDueTime)
        #expect(draft.start == (isWeekend ? cal.startOfDay(for: Date()) : upcoming(6)))
    }

    @Test func nextWeekIsNextMonday() {
        let draft = parse("Plan the trip next week")
        #expect(draft.title == "Plan the trip")
        #expect(draft.isAllDay)
        #expect(draft.start == cal.nextDate(after: cal.startOfDay(for: Date()), matching: DateComponents(weekday: 2), matchingPolicy: .nextTime))
    }

    @Test func theWeekendIsSaturday() {
        let draft = parse("Hike this weekend")
        #expect(draft.title == "Hike")
        #expect(draft.start == (isWeekend ? cal.startOfDay(for: Date()) : upcoming(7)))
    }

    @Test func nextWeekendIsLeftAlone() {
        #expect(!parse("Hike next weekend").hasExplicitDate)
    }
}
