import Foundation
import Testing
@testable import SoonbarCore

@Suite struct MeetingBriefBuilderTests {
    let start = Fixture.date(2026, 9, 29, 10, 0)

    func event(location: String? = nil, url: URL? = nil, notes: String? = nil, attendees: [Attendee] = []) -> CalendarEvent {
        var event = Fixture.event("Design review", start, start.addingTimeInterval(1800))
        event.location = location
        event.url = url
        event.notes = notes
        event.attendees = attendees
        return event
    }

    // MARK: Attendees

    @Test func organizerFirstThenByResponse() {
        let attendees = [
            Attendee(name: "Dee", status: .declined),
            Attendee(name: "Pat", status: .pending),
            Attendee(name: "Tia", status: .tentative),
            Attendee(name: "Bea", status: .accepted),
            Attendee(name: "Uma", status: .unknown),
            Attendee(name: "Ola", status: .unknown, isOrganizer: true),
            Attendee(name: "Ann", status: .accepted),
        ]
        #expect(MeetingBriefBuilder.sorted(attendees).compactMap(\.name) == ["Ola", "Ann", "Bea", "Tia", "Pat", "Uma", "Dee"])
    }

    @Test func displayNameFallsBackToEmailAndSaysYouForMe() {
        #expect(MeetingBriefBuilder.displayName(Attendee(name: "Jane Doe", email: "jane@bluebird.com")) == "Jane Doe")
        #expect(MeetingBriefBuilder.displayName(Attendee(name: "  ", email: "jane@bluebird.com")) == "jane@bluebird.com")
        #expect(MeetingBriefBuilder.displayName(Attendee(email: "jane@bluebird.com")) == "jane@bluebird.com")
        #expect(MeetingBriefBuilder.displayName(Attendee(name: "Alex Kim", isCurrentUser: true)) == "You")
        #expect(MeetingBriefBuilder.displayName(Attendee()) == "Unknown")
    }

    @Test func longAttendeeListsAreCappedWithACountOfTheRest() {
        let ten = (1...10).map { Attendee(email: "person\($0)@northwind.io", status: .accepted) }
        let brief = MeetingBriefBuilder.build(for: event(attendees: ten), maxAttendees: 8)
        #expect(brief.attendees.count == 7)
        #expect(brief.moreAttendees == 3)

        let eight = MeetingBriefBuilder.build(for: event(attendees: Array(ten.prefix(8))), maxAttendees: 8)
        #expect(eight.attendees.count == 8)
        #expect(eight.moreAttendees == 0)
    }

    // MARK: Links

    @Test func notesLinksExcludeTheMeetingAndItsProvider() {
        let notes = """
        Agenda: https://docs.bluebird.com/agenda.
        Join: https://acme.zoom.us/j/123456?pwd=x
        Local numbers: https://acme.zoom.us/u/abc
        Board https://www.trello.com/b/xyz and again https://docs.bluebird.com/agenda
        """
        let brief = MeetingBriefBuilder.build(for: event(notes: notes))
        #expect(brief.meetingLink?.provider == .zoom)
        #expect(brief.links.map(\.url.absoluteString) == ["https://docs.bluebird.com/agenda", "https://www.trello.com/b/xyz"])
        #expect(brief.links.map(\.title) == ["docs.bluebird.com", "trello.com"])
    }

    @Test func htmlAnchorTextBecomesTheLinkTitle() {
        let notes = #"See <a href="https://docs.bluebird.com/d/1?a=1&amp;b=2">Q3 <b>plan</b></a> and <a href="https://northwind.io/x">https://northwind.io/x</a>"#
        let links = MeetingBriefBuilder.build(for: event(notes: notes)).links
        #expect(links.map(\.url.absoluteString) == ["https://docs.bluebird.com/d/1?a=1&b=2", "https://northwind.io/x"])
        #expect(links.map(\.title) == ["Q3 plan", "northwind.io"])
    }

    @Test func eventURLComesFirstAndIsListedOnce() {
        let url = URL(string: "https://northwind.io/project")!
        let notes = "Doc https://docs.bluebird.com/a\nProject: https://northwind.io/project"
        let brief = MeetingBriefBuilder.build(for: event(url: url, notes: notes))
        #expect(brief.links.map(\.url) == [url, URL(string: "https://docs.bluebird.com/a")!])
        #expect(MeetingBriefBuilder.build(for: event(url: URL(string: "https://meet.google.com/abc-defg-hij"))).links.isEmpty)
    }

    // MARK: Notes

    @Test func notesKeepTheFirstLinesOfRealText() {
        let notes = "Goals:\n\n- Pick a logo\n- Agree on dates\nhttps://docs.bluebird.com/x\n- Budget\n- Next steps"
        #expect(MeetingBriefBuilder.build(for: event(notes: notes), maxNoteLines: 4).notes
            == "Goals:\n- Pick a logo\n- Agree on dates\n- Budget…")
        #expect(MeetingBriefBuilder.build(for: event(notes: "Short\nnote")).notes == "Short\nnote")
    }

    @Test func notesStopAtTheInvitationBoilerplate() {
        let notes = """
        Bring the mockups.
        ________________________________________________________________________________
        Microsoft Teams meeting
        Join: https://teams.microsoft.com/l/meetup-join/abc
        """
        #expect(MeetingBriefBuilder.build(for: event(notes: notes)).notes == "Bring the mockups.")
    }

    @Test func notesThatAreOnlyBoilerplateStillShowItsText() {
        let notes = "-::~:~::~:~::~:~::-\nJoin with Google Meet: https://meet.google.com/abc-defg-hij\nMeeting ID: abc"
        #expect(MeetingBriefBuilder.build(for: event(notes: notes)).notes == "Meeting ID: abc")
        #expect(MeetingBriefBuilder.build(for: event(notes: "<br>\n https://northwind.io ")).notes == nil)
        #expect(MeetingBriefBuilder.build(for: event()).notes == nil)
    }

    @Test func htmlNotesBecomePlainText() {
        #expect(MeetingBriefBuilder.build(for: event(notes: "<p>Bring <b>mockups</b> &amp; notes</p>")).notes
            == "Bring mockups & notes")
    }

    // MARK: Location

    @Test func locationIsHiddenWhenItIsJustTheMeetingLink() {
        #expect(MeetingBriefBuilder.build(for: event(location: "https://meet.google.com/abc-defg-hij")).location == nil)
        #expect(MeetingBriefBuilder.build(for: event(location: "Room 4; https://acme.zoom.us/j/123")).location == "Room 4")
        #expect(MeetingBriefBuilder.build(for: event(location: "Room 4")).location == "Room 4")
        #expect(MeetingBriefBuilder.build(for: event(location: " ")).location == nil)
    }

    @Test func meetingLinkComesFromTheEventLikeEverywhereElse() {
        let brief = MeetingBriefBuilder.build(for: event(location: "https://meet.google.com/abc-defg-hij"))
        #expect(brief.meetingLink?.provider == .googleMeet)
    }

    // MARK: Status

    @Test func statusCountsDownThenUp() {
        let calendar = Fixture.calendar
        let locale = Fixture.locale
        #expect(MeetingBriefBuilder.status(start: start, now: start.addingTimeInterval(-300), calendar: calendar, locale: locale) == "in 5m")
        #expect(MeetingBriefBuilder.status(start: start, now: start.addingTimeInterval(-30), calendar: calendar, locale: locale) == "now")
        #expect(MeetingBriefBuilder.status(start: start, now: start.addingTimeInterval(30), calendar: calendar, locale: locale) == "now")
        #expect(MeetingBriefBuilder.status(start: start, now: start.addingTimeInterval(130), calendar: calendar, locale: locale) == "started 2m ago")
    }
}
