import Foundation
import Testing
@testable import SoonbarCore

@Suite struct MeetingBriefPlannerTests {
    let now = Fixture.date(2026, 9, 29, 10, 0)
    let jane = Attendee(name: "Jane Doe", email: "jane@bluebird.com", status: .accepted)
    let me = Attendee(name: "Alex Kim", email: "alex@northwind.io", status: .accepted, isCurrentUser: true)

    func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        Fixture.date(2026, 9, 29, hour, minute).addingTimeInterval(TimeInterval(second))
    }

    func meeting(_ title: String, _ start: Date, _ end: Date, attendees: [Attendee]? = nil) -> CalendarEvent {
        var event = Fixture.event(title, start, end)
        event.attendees = attendees ?? [me, jane]
        return event
    }

    func due(
        _ events: [CalendarEvent], now: Date? = nil, lead: Int = 5, onlyWithAttendees: Bool = false, briefed: Set<String> = []
    ) -> [String] {
        MeetingBriefPlanner.dueBriefs(
            events: events, now: now ?? self.now,
            settings: MeetingBriefSettings(leadMinutes: lead, onlyWithAttendees: onlyWithAttendees),
            alreadyBriefed: briefed
        ).map(\.title)
    }

    @Test func dueWhenTheLeadTimeIsReached() {
        #expect(due([meeting("Sync", at(10, 5), at(10, 30))]) == ["Sync"])
        #expect(due([meeting("Sync", at(10, 6), at(10, 30))]).isEmpty)
        #expect(due([meeting("Sync", at(10, 10), at(10, 30))], lead: 10) == ["Sync"])
    }

    @Test func stillDueShortlyAfterTheStartButNotLater() {
        // Waking up at 10:01 for a 10:00 meeting: the brief still helps while joining.
        #expect(due([meeting("Standup", at(9, 59), at(10, 15))]) == ["Standup"])
        #expect(due([meeting("Standup", at(9, 58), at(10, 15))]).isEmpty)
    }

    @Test func skipsAllDayDeclinedCancelledAndAlreadyBriefed() {
        var allDay = meeting("Offsite", Fixture.date(2026, 9, 29), Fixture.date(2026, 9, 30))
        allDay.isAllDay = true
        var declined = meeting("Declined", at(10, 5), at(10, 30))
        declined.isDeclined = true
        var cancelled = meeting("Cancelled", at(10, 5), at(10, 30))
        cancelled.isCancelled = true
        let briefed = meeting("Briefed", at(10, 5), at(10, 30))
        #expect(due([allDay, declined, cancelled, briefed], briefed: [briefed.id]).isEmpty)
    }

    @Test func onlyWithAttendeesNeedsSomeoneOtherThanMe() {
        let solo = meeting("Focus", at(10, 5), at(11), attendees: [])
        let justMe = meeting("Just me", at(10, 5), at(11), attendees: [me])
        let shared = meeting("Shared", at(10, 5), at(11))
        #expect(due([solo, justMe, shared], onlyWithAttendees: true) == ["Shared"])
        #expect(due([solo, justMe, shared]) == ["Focus", "Just me", "Shared"])
    }

    @Test func dueBriefsAreInStartOrder() {
        let events = [meeting("B", at(10, 4), at(10, 30)), meeting("A", at(10, 2), at(10, 30))]
        #expect(due(events) == ["A", "B"])
    }

    @Test func nextBriefDateIsTheEarliestUpcomingBriefMoment() {
        let a = meeting("A", at(10, 30), at(11))
        let b = meeting("B", at(11), at(11, 30))
        let started = meeting("Started", at(9), at(10, 30))
        let settings = MeetingBriefSettings(leadMinutes: 5)
        #expect(MeetingBriefPlanner.nextBriefDate(events: [b, a, started], now: now, settings: settings, alreadyBriefed: []) == at(10, 25))
        #expect(MeetingBriefPlanner.nextBriefDate(events: [b, a], now: now, settings: settings, alreadyBriefed: [a.id]) == at(10, 55))
        #expect(MeetingBriefPlanner.nextBriefDate(events: [started], now: now, settings: settings, alreadyBriefed: []) == nil)
    }

    @Test func dismissesTwoMinutesAfterTheStart() {
        #expect(MeetingBriefPlanner.dismissDate(for: meeting("Sync", at(10), at(10, 30))) == at(10, 2))
    }

    @Test func nextMeetingForPreviewSkipsEndedAndFilteredEvents() {
        let ended = meeting("Ended", at(9), at(9, 30))
        let solo = meeting("Focus", at(10, 30), at(11), attendees: [])
        let shared = meeting("Shared", at(11), at(12))
        let settings = MeetingBriefSettings(leadMinutes: 5, onlyWithAttendees: true)
        #expect(MeetingBriefPlanner.nextMeeting(events: [ended, solo, shared], now: now, settings: settings)?.title == "Shared")
    }
}
