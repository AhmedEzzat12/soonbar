import Foundation
import Testing
@testable import SoonbarCore

struct InviteStatusTests {
    let now = Fixture.date(2026, 10, 8, 9)

    func invite(_ title: String, day: Int, _ status: Attendee.Status, series: String? = nil, organizer: Bool = false, cancelled: Bool = false) -> CalendarEvent {
        let start = Fixture.date(2026, 10, day, 10)
        return CalendarEvent(
            id: "\(title)-\(day)", eventIdentifier: series, title: title, start: start, end: start.addingTimeInterval(3600),
            calendarID: "work", isCancelled: cancelled,
            attendees: [Attendee(name: "Me", status: status, isOrganizer: organizer, isCurrentUser: true),
                        Attendee(name: "Sam", status: .accepted)]
        )
    }

    @Test func myResponseIsOnlyForInvitations() {
        #expect(invite("A", day: 9, .pending).myResponse == .pending)
        #expect(invite("Mine", day: 9, .accepted, organizer: true).myResponse == nil)
        #expect(Fixture.event("Solo", now, now.addingTimeInterval(60)).myResponse == nil)
    }

    @Test func awaitingReplySkipsPastCancelledAndRepeatsOfASeries() {
        let events = [
            invite("Later", day: 12, .pending),
            invite("Weekly", day: 9, .pending, series: "weekly"),
            invite("Weekly", day: 16, .pending, series: "weekly"),
            invite("Past", day: 7, .pending),
            invite("Called off", day: 10, .pending, cancelled: true),
            invite("Answered", day: 11, .accepted),
        ]
        #expect(InviteStatus.awaitingReply(events: events, now: now).map(\.title) == ["Weekly", "Later"])
    }

    @Test func maybeAndUnansweredAreUnconfirmed() {
        #expect(InviteStatus.isUnconfirmed(invite("A", day: 9, .pending)))
        #expect(InviteStatus.isUnconfirmed(invite("B", day: 9, .tentative)))
        #expect(!InviteStatus.isUnconfirmed(invite("C", day: 9, .accepted)))
    }
}
