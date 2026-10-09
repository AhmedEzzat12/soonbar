import Foundation
import Testing
@testable import SoonbarCore

struct SecondTimeZoneTests {
    let cal = Fixture.calendar
    let newYork = TimeZone(identifier: "America/New_York")!

    func range(_ start: Date, _ end: Date, _ zone: TimeZone, allDay: Bool = false) -> String? {
        SecondTimeZone.timeRange(for: Fixture.event("M", start, end, allDay: allDay), in: zone, calendar: cal, locale: Fixture.locale)
    }

    @Test func showsTheMeetingInTheOtherZone() {
        #expect(range(Fixture.date(2026, 10, 8, 15), Fixture.date(2026, 10, 8, 16), newYork) == "09:00–10:00 New York")
    }

    @Test func marksAnotherDay() {
        #expect(range(Fixture.date(2026, 10, 8, 3), Fixture.date(2026, 10, 8, 4), newYork) == "21:00–22:00 (−1) New York")
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(range(Fixture.date(2026, 10, 8, 18), Fixture.date(2026, 10, 8, 19), tokyo) == "01:00–02:00 (+1) Tokyo")
    }

    @Test func nothingForTheSameClockOrAllDayEvents() {
        #expect(range(Fixture.date(2026, 10, 8, 15), Fixture.date(2026, 10, 8, 16), TimeZone(identifier: "Europe/Paris")!) == nil)
        #expect(range(Fixture.date(2026, 10, 8), Fixture.date(2026, 10, 9), newYork, allDay: true) == nil)
    }

    @Test func cityNames() {
        #expect(SecondTimeZone.cityName(newYork) == "New York")
        #expect(SecondTimeZone.cityName(TimeZone(identifier: "America/Argentina/Buenos_Aires")!) == "Buenos Aires")
        // Zones without a region keep their identifier (Apple reports UTC as "GMT").
        #expect(SecondTimeZone.cityName(TimeZone(identifier: "UTC")!) == TimeZone(identifier: "UTC")!.identifier)
    }

    @Test func clockShowsTheTimeThere() {
        #expect(SecondTimeZone.clock(now: Fixture.date(2026, 10, 8, 9, 12), zone: newYork, calendar: cal, locale: Fixture.locale) == "New York 03:12")
    }
}
