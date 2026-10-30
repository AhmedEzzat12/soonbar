import Foundation
import Testing
@testable import SoonbarCore

@Suite struct MeetingAlertPlannerTests {
    let now = Fixture.date(2026, 9, 29, 10, 0)

    func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        Fixture.date(2026, 9, 29, hour, minute).addingTimeInterval(TimeInterval(second))
    }

    func settings(lead: [Int] = [0], videoOnly: Bool = false) -> MeetingAlertSettings {
        MeetingAlertSettings(leadMinutes: lead, onlyWithVideoLink: videoOnly)
    }

    func due(_ events: [CalendarEvent], now: Date? = nil, lead: [Int] = [0], videoOnly: Bool = false,
             state: MeetingAlertState = MeetingAlertState()) -> [String] {
        MeetingAlertPlanner.dueAlerts(events: events, now: now ?? self.now, settings: settings(lead: lead, videoOnly: videoOnly), state: state)
            .map(\.event.title)
    }

    func state(shown: Set<String> = [], finished: Set<String> = [], snoozed: [String: Date] = [:]) -> MeetingAlertState {
        var state = MeetingAlertState()
        state.shown = shown
        state.finished = finished
        state.snoozed = snoozed
        return state
    }

    @Test func eventStartingNowIsDue() {
        #expect(due([Fixture.event("Standup", at(10), at(10, 15))]) == ["Standup"])
    }

    @Test func futureEventIsNotDueYet() {
        #expect(due([Fixture.event("Later", at(10, 5), at(10, 30))]).isEmpty)
    }

    @Test func leadTimeMakesItDueEarlier() {
        #expect(due([Fixture.event("Sync", at(10, 2), at(10, 30))], lead: [2]) == ["Sync"])
        #expect(due([Fixture.event("Sync", at(10, 3), at(10, 30))], lead: [2]).isEmpty)
    }

    @Test func missedByMoreThanTheGraceWindowIsSkipped() {
        // Laptop woke at 10:03 for a 10:00 meeting: too late for a full-screen interruption.
        #expect(due([Fixture.event("Standup", at(9, 57), at(10, 30))]).isEmpty)
        #expect(due([Fixture.event("Standup", at(9, 59), at(10, 30))]) == ["Standup"])
    }

    @Test func shownJoinedAllDayDeclinedAndCancelledAreSkipped() {
        let events = [
            Fixture.event("Done", at(10), at(10, 30)),
            Fixture.event("Holiday", Fixture.date(2026, 9, 29), Fixture.date(2026, 9, 30), allDay: true),
            Fixture.event("Declined", at(10), at(10, 30), declined: true),
            Fixture.event("Cancelled", at(10), at(10, 30), cancelled: true),
        ]
        #expect(due(events, state: state(shown: ["\(events[0].id)|lead:0"])).isEmpty)
        #expect(due(events, state: state(finished: [events[0].id])).isEmpty)
    }

    @Test func videoOnlyRequiresAMeetingLink() {
        var call = Fixture.event("Call", at(10), at(10, 30))
        call.location = "https://meet.google.com/abc-defg-hij"
        let lunch = Fixture.event("Lunch", at(10), at(11))
        #expect(due([call, lunch], videoOnly: true) == ["Call"])
        #expect(due([call, lunch]) == ["Call", "Lunch"])
    }

    @Test func nextAlertDateIsTheEarliestUpcomingAlertMoment() {
        let events = [
            Fixture.event("B", at(11), at(11, 30)),
            Fixture.event("A", at(10, 30), at(11)),
            Fixture.event("Started", at(9), at(10, 30)),
        ]
        #expect(MeetingAlertPlanner.nextAlertDate(events: events, now: now, settings: settings(lead: [1]), state: state()) == at(10, 29))
    }

    @Test func nextAlertDateIgnoresAlertedEvents() {
        let a = Fixture.event("A", at(10, 30), at(11))
        let b = Fixture.event("B", at(11), at(11, 30))
        #expect(MeetingAlertPlanner.nextAlertDate(events: [a, b], now: now, settings: settings(), state: state(finished: [a.id])) == at(11))
    }

    // MARK: - Several lead times, snooze, join

    @Test func eachLeadTimeFiresOnce() {
        let sync = Fixture.event("Sync", at(10, 10), at(10, 40))
        let first = MeetingAlertPlanner.dueAlerts(events: [sync], now: at(10, 5), settings: settings(lead: [5, 0]), state: state())
        #expect(first.map(\.keys) == [["\(sync.id)|lead:5"]])
        let shown = state(shown: ["\(sync.id)|lead:5"])
        #expect(due([sync], now: at(10, 6), lead: [5, 0], state: shown).isEmpty)
        #expect(due([sync], now: at(10, 10), lead: [5, 0], state: shown) == ["Sync"])
        #expect(MeetingAlertPlanner.nextAlertDate(events: [sync], now: at(10, 6), settings: settings(lead: [5, 0]), state: shown) == at(10, 10))
    }

    @Test func momentsDueTogetherMakeOneAlert() {
        // Woke at 10:00 with alerts set for 5 and 1 minutes before and at the start: one alert covers the last two;
        // the 9:55 one is past the grace window and is skipped rather than shown late.
        let standup = Fixture.event("Standup", at(10), at(10, 15))
        let alerts = MeetingAlertPlanner.dueAlerts(events: [standup], now: at(10), settings: settings(lead: [5, 1, 0]), state: state())
        #expect(alerts.count == 1)
        #expect(alerts.first?.keys == ["\(standup.id)|lead:1", "\(standup.id)|lead:0"])
    }

    @Test func snoozedMeetingAlertsAgain() {
        let review = Fixture.event("Review", at(10), at(10, 30))
        let snoozed = state(shown: ["\(review.id)|lead:0"], snoozed: [review.id: at(10, 2)])
        #expect(due([review], now: at(10, 1), state: snoozed).isEmpty)
        #expect(due([review], now: at(10, 2), state: snoozed) == ["Review"])
        #expect(MeetingAlertPlanner.nextAlertDate(events: [review], now: at(10, 1), settings: settings(), state: snoozed) == at(10, 2))
    }

    @Test func snoozeEndsWithTheMeeting() {
        let short = Fixture.event("Short", at(10), at(10, 5))
        #expect(MeetingAlertPlanner.snoozeDate(for: short, now: at(10), minutes: 2) == at(10, 2))
        #expect(MeetingAlertPlanner.snoozeDate(for: short, now: at(10, 4), minutes: 2) == nil)
    }

    @Test func joinedMeetingGetsNoMoreAlerts() {
        let sync = Fixture.event("Sync", at(10, 5), at(10, 30))
        let joined = state(finished: [sync.id], snoozed: [sync.id: at(10, 1)])
        #expect(due([sync], now: at(10, 1), lead: [5, 0], state: joined).isEmpty)
        #expect(MeetingAlertPlanner.nextAlertDate(events: [sync], now: now, settings: settings(lead: [5, 0]), state: joined) == nil)
    }

    @Test func stateForgetsMeetingsThatAreGone() {
        var kept = state(shown: ["a|lead:0", "b|lead:5"], finished: ["a", "b"], snoozed: ["b": at(10)])
        kept.keep(eventIDs: ["a"])
        #expect(kept.shown == ["a|lead:0"])
        #expect(kept.finished == ["a"])
        #expect(kept.snoozed.isEmpty)
    }

    @Test func leadTimesAreDeduplicatedAndOrdered() {
        #expect(MeetingAlertSettings(leadMinutes: [0, 5, 5, 15, -1]).leadMinutes == [15, 5, 0])
    }
}
