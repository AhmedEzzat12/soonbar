import Foundation
import Testing
@testable import SoonbarCore

@Suite struct AvailabilityFormatterTests {
    let cal = Fixture.calendar

    func text(
        _ events: [CalendarEvent], now: Date, days: Int = 2, timeZone: Bool = true,
        calendar: Calendar = Fixture.calendar, locale: Locale = Fixture.locale
    ) -> String? {
        let settings = AvailabilitySettings(workingDays: days, workingHours: .standard, minimumMinutes: 30)
        let plan = AvailabilityPlanner.days(events: events, now: now, settings: settings, calendar: calendar)
        return AvailabilityFormatter.text(plan, includeTimeZone: timeZone, calendar: calendar, locale: locale)
    }

    let meetings = [
        Fixture.event("Standup", Fixture.date(2026, 10, 6, 9), Fixture.date(2026, 10, 6, 10)),
        Fixture.event("Review", Fixture.date(2026, 10, 6, 11, 30), Fixture.date(2026, 10, 6, 14)),
        Fixture.event("Workshop", Fixture.date(2026, 10, 6, 17), Fixture.date(2026, 10, 6, 18)),
    ]

    @Test func oneLinePerDayWithTimeZone() {
        #expect(text(meetings, now: Fixture.date(2026, 10, 6, 8)) == """
        Tue 6 Oct: 10:00–11:30, 14:00–17:00
        Wed 7 Oct: free all day (09:00–18:00)
        (times in CEST)
        """)
    }

    @Test func timesCanBeWrittenInTheOtherPersonsZone() {
        let settings = AvailabilitySettings(workingDays: 2, workingHours: .standard, minimumMinutes: 30)
        let plan = AvailabilityPlanner.days(events: meetings, now: Fixture.date(2026, 10, 6, 8), settings: settings, calendar: cal)
        let newYork = TimeZone(identifier: "America/New_York")!
        let text = AvailabilityFormatter.text(plan, includeTimeZone: false, calendar: cal, locale: Fixture.locale, displayTimeZone: newYork)
        #expect(text == """
        Tue 6 Oct: 04:00–05:30, 08:00–11:00
        Wed 7 Oct: 03:00–12:00
        """)
    }

    @Test func otherZoneRegroupsByItsOwnDates() {
        let settings = AvailabilitySettings(workingDays: 2, workingHours: .standard, minimumMinutes: 30)
        let plan = AvailabilityPlanner.days(events: meetings, now: Fixture.date(2026, 10, 6, 8), settings: settings, calendar: cal)
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        let text = AvailabilityFormatter.text(plan, includeTimeZone: true, calendar: cal, locale: Fixture.locale, displayTimeZone: auckland)
        let lines = text?.components(separatedBy: "\n") ?? []
        #expect(lines.prefix(2) == ["Tue 6 Oct: 21:00–22:30", "Wed 7 Oct: 01:00–04:00, 20:00–05:00"])
        #expect(lines.last?.hasPrefix("(times in ") == true)
    }

    @Test func sameOffsetZoneKeepsTheNormalFormat() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let settings = AvailabilitySettings(workingDays: 1, workingHours: .standard, minimumMinutes: 30)
        let plan = AvailabilityPlanner.days(events: meetings, now: Fixture.date(2026, 10, 6, 8), settings: settings, calendar: cal)
        #expect(AvailabilityFormatter.text(plan, includeTimeZone: false, calendar: cal, locale: Fixture.locale, displayTimeZone: paris)
                == "Tue 6 Oct: 10:00–11:30, 14:00–17:00")
    }

    @Test func timeZoneLineIsOptional() {
        #expect(text(meetings, now: Fixture.date(2026, 10, 6, 8), days: 1, timeZone: false) == "Tue 6 Oct: 10:00–11:30, 14:00–17:00")
    }

    @Test func todayIsNotFreeAllDayOnceWorkHasStarted() {
        #expect(text([], now: Fixture.date(2026, 10, 6, 10, 5), days: 1, timeZone: false) == "Tue 6 Oct: 10:15–18:00")
    }

    @Test func daysWithNothingFreeAreSkipped() {
        let offsite = Fixture.event("Offsite", Fixture.date(2026, 10, 6, 9), Fixture.date(2026, 10, 6, 18))
        #expect(text([offsite], now: Fixture.date(2026, 10, 6, 8), timeZone: false) == "Wed 7 Oct: free all day (09:00–18:00)")
    }

    @Test func nothingFreeGivesNil() {
        let offsite = Fixture.event("Offsite", Fixture.date(2026, 10, 6, 9), Fixture.date(2026, 10, 7, 18))
        #expect(text([offsite], now: Fixture.date(2026, 10, 6, 8)) == nil)
        #expect(AvailabilityFormatter.text([], includeTimeZone: true, calendar: cal, locale: Fixture.locale) == nil)
    }

    @Test func winterTimeUsesTheStandardName() {
        #expect(text([], now: Fixture.date(2026, 11, 3, 8), days: 1) == "Tue 3 Nov: free all day (09:00–18:00)\n(times in CET)")
    }

    @Test func followsTheLocale() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let us = Locale(identifier: "en_US")
        let now = newYork.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 8))!
        // Newer ICU puts a narrow no-break space before AM/PM.
        let result = text([], now: now, days: 1, calendar: newYork, locale: us)?
            .replacingOccurrences(of: "\u{202F}", with: " ")
        #expect(result == "Tue, Oct 6: free all day (9:00 AM–6:00 PM)\n(times in EDT)")
    }

    @Test func timeZoneNameIsLocalized() {
        let german = Locale(identifier: "de_DE")
        #expect(AvailabilityFormatter.timeZoneName(Fixture.timeZone, at: Fixture.date(2026, 7, 1), locale: german) == "MESZ")
    }
}
