import Foundation
import Testing
@testable import SoonbarCore

@Suite struct MeetingAutomationTrackerTests {
    typealias State = MeetingAutomationTracker.State

    func at(_ hour: Int, _ minute: Int = 0) -> Date { Fixture.date(2026, 9, 29, hour, minute) }

    func meeting(_ title: String, _ start: Date, _ end: Date, video: Bool = false) -> CalendarEvent {
        var event = Fixture.event(title, start, end)
        if video { event.url = URL(string: "https://zoom.us/j/123456789") }
        return event
    }

    /// Feeds the tracker one evaluation per time, starting from `state` (nil = just launched), and collects
    /// what it asked to run.
    func run(
        _ events: [CalendarEvent], at times: [Date], from state: State? = .idle,
        enabled: Bool = true, videoOnly: Bool = false
    ) -> (actions: [(Date, MeetingAutomationAction)], state: State?) {
        var state = state
        var actions: [(Date, MeetingAutomationAction)] = []
        let settings = MeetingAutomationSettings(isEnabled: enabled, onlyWithVideoLink: videoOnly)
        for time in times {
            let result = MeetingAutomationTracker.evaluate(previous: state, events: events, now: time, settings: settings)
            actions += result.actions.map { (time, $0) }
            state = result.state
        }
        return (actions, state)
    }

    func minutes(from start: Date, to end: Date) -> [Date] {
        stride(from: start, through: end, by: 60).map { $0 }
    }

    func describe(_ actions: [(Date, MeetingAutomationAction)]) -> [String] {
        let calendar = Fixture.calendar
        return actions.map { date, action in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d %@", parts.hour!, parts.minute!, action == .start ? "start" : "end")
        }
    }

    @Test func runsStartAndEndAroundAMeeting() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        let result = run(events, at: minutes(from: at(9, 58), to: at(10, 32)))
        #expect(describe(result.actions) == ["10:00 start", "10:30 end"])
        #expect(result.state == .idle)
    }

    @Test func backToBackMeetingsAreOneBlock() {
        let events = [meeting("A", at(10), at(10, 30)), meeting("B", at(10, 30), at(11))]
        #expect(describe(run(events, at: minutes(from: at(9, 59), to: at(11, 1))).actions) == ["10:00 start", "11:00 end"])
    }

    @Test func overlappingMeetingsAreOneBlock() {
        let events = [meeting("A", at(10), at(11)), meeting("B", at(10, 30), at(10, 45)), meeting("C", at(10, 50), at(11, 15))]
        #expect(describe(run(events, at: minutes(from: at(9, 59), to: at(11, 20))).actions) == ["10:00 start", "11:15 end"])
    }

    @Test func aOneMinuteGapEndsAndStartsAgain() {
        let events = [meeting("A", at(10), at(10, 30)), meeting("B", at(10, 31), at(11))]
        #expect(describe(run(events, at: minutes(from: at(9, 59), to: at(11, 1))).actions)
            == ["10:00 start", "10:30 end", "10:31 start", "11:00 end"])
    }

    @Test func aMissedTickBetweenTwoMeetingsStillEndsAndStarts() {
        let events = [meeting("A", at(10), at(10, 30)), meeting("B", at(10, 31), at(11))]
        let result = run(events, at: [at(10), at(10, 31)])
        #expect(describe(result.actions) == ["10:00 start", "10:31 end", "10:31 start"])
    }

    @Test func launchInTheMiddleOfAMeetingDoesNotStartButStillEnds() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        let launch = run(events, at: [at(10, 10)], from: nil)
        #expect(launch.actions.isEmpty)
        #expect(launch.state == .inMeeting(.init(start: at(10), end: at(10, 30), startRan: false)))
        #expect(describe(run(events, at: minutes(from: at(10, 11), to: at(10, 31)), from: launch.state).actions) == ["10:30 end"])
    }

    @Test func launchOutsideAMeetingIsIdle() {
        let result = run([meeting("Sync", at(10), at(10, 30))], at: [at(9)], from: nil)
        #expect(result.actions.isEmpty)
        #expect(result.state == .idle)
    }

    @Test func aLateTickWithinTheGraceWindowStillStarts() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        #expect(describe(run(events, at: [at(9, 50), at(10, 4)]).actions) == ["10:04 start"])
    }

    @Test func wakingLongAfterAMeetingStartedDoesNotStartIt() {
        let events = [meeting("Sync", at(10), at(11))]
        let result = run(events, at: [at(9, 50), at(10, 20)])
        #expect(result.actions.isEmpty)
        #expect(describe(run(events, at: [at(11)], from: result.state).actions) == ["11:00 end"])
    }

    @Test func wakingAfterAMeetingEndedRunsEndOnlyIfStartRan() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        let started = run(events, at: [at(10)])
        #expect(describe(run(events, at: [at(12)], from: started.state).actions) == ["12:00 end"])

        let joinedLate = run(events, at: [at(10, 10)])
        #expect(run(events, at: [at(12)], from: joinedLate.state).actions.isEmpty)
    }

    @Test func wakingIntoTheNextMeetingEndsTheOldBlockAndStartsTheNewOne() {
        let events = [meeting("A", at(10), at(10, 30)), meeting("B", at(14), at(15))]
        let result = run(events, at: [at(10), at(14, 1)])
        #expect(describe(result.actions) == ["10:00 start", "14:01 end", "14:01 start"])
    }

    @Test func wakingLateIntoTheNextMeetingOnlyEndsTheOldBlock() {
        let events = [meeting("A", at(10), at(10, 30)), meeting("B", at(14), at(15))]
        let result = run(events, at: [at(10), at(14, 30)])
        #expect(describe(result.actions) == ["10:00 start", "14:30 end"])
        #expect(result.state == .inMeeting(.init(start: at(14), end: at(15), startRan: false)))
    }

    @Test func aMeetingThatIsExtendedKeepsTheBlockGoing() {
        let original = [meeting("Sync", at(10), at(10, 30))]
        let extended = [meeting("Sync", at(10), at(11))]
        let started = run(original, at: [at(10)])
        let later = run(extended, at: minutes(from: at(10, 1), to: at(11)), from: started.state)
        #expect(describe(later.actions) == ["11:00 end"])
    }

    @Test func declinedCancelledAndAllDayEventsAreNotMeetings() {
        let events = [
            Fixture.event("Declined", at(10), at(10, 30), declined: true),
            Fixture.event("Cancelled", at(10), at(10, 30), cancelled: true),
            Fixture.event("Holiday", Fixture.date(2026, 9, 29), Fixture.date(2026, 9, 30), allDay: true),
        ]
        #expect(run(events, at: minutes(from: at(9, 59), to: at(10, 31))).actions.isEmpty)
    }

    @Test func decliningAMeetingWhileInItEndsTheBlock() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        var declined = events
        declined[0].isDeclined = true
        let started = run(events, at: [at(10)])
        #expect(describe(run(declined, at: [at(10, 10)], from: started.state).actions) == ["10:10 end"])
    }

    @Test func videoOnlyIgnoresMeetingsWithoutALink() {
        let events = [meeting("Lunch", at(10), at(11)), meeting("Call", at(11), at(11, 30), video: true)]
        let times = minutes(from: at(9, 59), to: at(11, 31))
        #expect(describe(run(events, at: times, videoOnly: true).actions) == ["11:00 start", "11:30 end"])
        #expect(describe(run(events, at: times).actions) == ["10:00 start", "11:30 end"])
    }

    @Test func disabledDoesNothingAndForgetsTheBlock() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        let disabled = run(events, at: minutes(from: at(9, 59), to: at(10, 31)), enabled: false)
        #expect(disabled.actions.isEmpty)
        #expect(disabled.state == nil)
    }

    @Test func turningOffMidMeetingDoesNotRunEnd() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        let started = run(events, at: [at(10)])
        let off = run(events, at: [at(10, 10)], from: started.state, enabled: false)
        #expect(off.actions.isEmpty)
        #expect(off.state == nil)
    }

    @Test func turningOnMidMeetingBehavesLikeLaunch() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        let off = run(events, at: [at(9, 59), at(10)], enabled: false)
        let on = run(events, at: minutes(from: at(10, 10), to: at(10, 31)), from: off.state)
        #expect(describe(on.actions) == ["10:30 end"])
    }

    @Test func endIsExclusiveAndStartIsInclusive() {
        let events = [meeting("Sync", at(10), at(10, 30))]
        let idle = State.idle
        #expect(MeetingAutomationTracker.evaluate(
            previous: idle, events: events, now: at(10), settings: .init(isEnabled: true)
        ).actions == [.start])
        let started = State.inMeeting(.init(start: at(10), end: at(10, 30), startRan: true))
        #expect(MeetingAutomationTracker.evaluate(
            previous: started, events: events, now: at(10, 30), settings: .init(isEnabled: true)
        ).actions == [.end])
    }
}
