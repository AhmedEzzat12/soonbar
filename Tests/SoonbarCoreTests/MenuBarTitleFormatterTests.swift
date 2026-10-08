import Foundation
import Testing
@testable import SoonbarCore

@Suite struct MenuBarTitleFormatterTests {
    let cal = Fixture.calendar
    let now = Fixture.date(2026, 9, 29, 10, 0)

    func at(_ hour: Int, _ minute: Int = 0, day: Int = 29) -> Date { Fixture.date(2026, 9, day, hour, minute) }

    func title(_ events: [CalendarEvent], window: MenuBarWindow = .restOfToday, max: Int = 25) -> String? {
        MenuBarTitleFormatter.title(
            events: events, now: now,
            settings: MenuBarTitleSettings(window: window, maxTitleLength: max),
            calendar: cal, locale: Fixture.locale
        )?.text
    }

    func timeLeft(_ events: [CalendarEvent], at time: Date? = nil, max: Int = 25) -> MenuBarTitle? {
        MenuBarTitleFormatter.title(
            events: events, now: time ?? now,
            settings: MenuBarTitleSettings(maxTitleLength: max, showMeetingTimeLeft: true),
            calendar: cal, locale: Fixture.locale
        )
    }

    @Test func nothingScheduledShowsNoTitle() {
        #expect(title([]) == nil)
    }

    @Test func imminentEventBeatsOngoingEvent() {
        let events = [Fixture.event("Focus", at(9, 30), at(10, 30)), Fixture.event("Standup", at(10, 8), at(10, 23))]
        #expect(title(events) == "Standup · in 8m")
    }

    @Test func ongoingEventShowsTimeLeft() {
        let events = [Fixture.event("Focus", at(9, 30), at(10, 30)), Fixture.event("Lunch", at(12), at(13))]
        #expect(title(events) == "Focus · 30m left")
    }

    @Test func ongoingEventEndingSoonestWins() {
        let events = [Fixture.event("Long", at(9), at(12)), Fixture.event("Short", at(9, 45), at(10, 20))]
        #expect(title(events) == "Short · 20m left")
    }

    @Test func laterTodayWithinDefaultWindow() {
        #expect(title([Fixture.event("Lunch", at(12), at(13))]) == "Lunch · in 2h")
    }

    @Test func narrowWindowHidesFarEvents() {
        #expect(title([Fixture.event("Lunch", at(12), at(13))], window: .oneHour) == nil)
    }

    @Test func tomorrowHiddenUnlessWindowIsAlways() {
        let events = [Fixture.event("Planning", at(9, day: 30), at(10, day: 30))]
        #expect(title(events) == nil)
        #expect(title(events, window: .always) == "Planning · Wed 09:00")
    }

    @Test func skipsAllDayDeclinedAndCancelled() {
        let events = [
            Fixture.event("Holiday", Fixture.date(2026, 9, 29), Fixture.date(2026, 9, 30), allDay: true),
            Fixture.event("Declined", at(10, 5), at(11), declined: true),
            Fixture.event("Cancelled", at(10, 6), at(11), cancelled: true),
            Fixture.event("Real", at(11), at(12)),
        ]
        #expect(title(events) == "Real · in 1h")
    }

    @Test func truncatesLongTitles() {
        let events = [Fixture.event("Quarterly planning with design team", at(10, 30), at(11))]
        #expect(title(events, max: 10) == "Quarterly… · in 30m")
    }

    @Test func truncationTrimsTrailingSpace() {
        #expect(MenuBarTitleFormatter.truncate("Team sync meeting", to: 6) == "Team…")
    }

    // MARK: Time left in the current meeting

    @Test func timeLeftBeatsImminentNextEvent() {
        let events = [Fixture.event("Focus", at(9, 30), at(10, 7)), Fixture.event("Standup", at(10, 8), at(10, 23))]
        #expect(timeLeft(events)?.text == "Focus · 7m left")
    }

    @Test func timeLeftShowsTheMeetingThatFollowsWithoutABreak() {
        let events = [Fixture.event("Standup", at(9, 45), at(10, 12)), Fixture.event("Design review", at(10, 12), at(11))]
        #expect(timeLeft(events)?.text == "Standup · 12m left → Design review")
    }

    @Test func timeLeftShowsAMeetingThatStartsBeforeThisOneEnds() {
        let events = [Fixture.event("Standup", at(9, 45), at(10, 15)), Fixture.event("Design review", at(10, 10), at(11))]
        #expect(timeLeft(events)?.text == "Standup · 15m left → Design review")
    }

    @Test func timeLeftOmitsANextMeetingAfterABreak() {
        let events = [Fixture.event("Standup", at(9, 45), at(10, 12)), Fixture.event("Design review", at(10, 13), at(11))]
        #expect(timeLeft(events)?.text == "Standup · 12m left")
    }

    @Test func timeLeftUsesTheOverlappingMeetingThatEndsFirst() {
        let events = [Fixture.event("Long", at(9), at(12)), Fixture.event("Short", at(9, 45), at(10, 20))]
        #expect(timeLeft(events)?.text == "Short · 20m left")
    }

    @Test func timeLeftIsUrgentInTheLastFiveMinutes() {
        let events = [Fixture.event("Standup", at(9, 45), at(10, 5))]
        #expect(timeLeft(events)?.isUrgent == true)
        #expect(timeLeft(events, at: at(9, 59))?.isUrgent == false)
    }

    @Test func timeLeftIsNeverUrgentWhenTheSettingIsOff() {
        let events = [Fixture.event("Standup", at(9, 45), at(10, 5))]
        let result = MenuBarTitleFormatter.title(
            events: events, now: now, settings: MenuBarTitleSettings(), calendar: cal, locale: Fixture.locale
        )
        #expect(result?.text == "Standup · 5m left")
        #expect(result?.isUrgent == false)
    }

    @Test func timeLeftSkipsAllDayDeclinedAndCancelled() {
        let events = [
            Fixture.event("Holiday", Fixture.date(2026, 9, 29), Fixture.date(2026, 9, 30), allDay: true),
            Fixture.event("Declined", at(9, 30), at(10, 10), declined: true),
            Fixture.event("Cancelled", at(9, 30), at(10, 20), cancelled: true),
            Fixture.event("Next", at(10, 8), at(11)),
        ]
        #expect(timeLeft(events)?.text == "Next · in 8m")
    }

    @Test func timeLeftIgnoresDeclinedFollowUp() {
        let events = [Fixture.event("Standup", at(9, 45), at(10, 12)), Fixture.event("Skip", at(10, 12), at(11), declined: true)]
        #expect(timeLeft(events)?.text == "Standup · 12m left")
    }

    @Test func timeLeftTruncatesBothTitles() {
        let events = [
            Fixture.event("Quarterly planning", at(9, 30), at(10, 3)),
            Fixture.event("Design review sync", at(10, 3), at(11)),
        ]
        #expect(timeLeft(events, max: 10)?.text == "Quarterly… · 3m left → Design re…")
    }

    @Test func timeLeftOutsideMeetingsShowsTheNextEvent() {
        #expect(timeLeft([Fixture.event("Lunch", at(12), at(13))])?.text == "Lunch · in 2h")
    }
}
