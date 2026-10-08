import Foundation
import Testing
@testable import SoonbarCore

@Suite struct BackToBackDetectorTests {
    let cal = Fixture.calendar

    func at(_ hour: Int, _ minute: Int = 0, day: Int = 29) -> Date { Fixture.date(2026, 9, day, hour, minute) }

    /// Title of each marked event → "after <previous>" or "overlaps <previous>".
    func marks(_ events: [CalendarEvent], gap: Int = 5) -> [String: String] {
        let links = BackToBackDetector.predecessors(events: events, gapMinutes: gap, calendar: cal)
        let titles = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.title) })
        return Dictionary(uniqueKeysWithValues: links.map { id, link in
            (titles[id]!, "\(link.overlaps ? "overlaps" : "after") \(link.previousTitle)")
        })
    }

    @Test func noEventsNoMarks() {
        #expect(marks([]).isEmpty)
    }

    @Test func meetingStartingWhenAnotherEndsIsMarked() {
        let events = [Fixture.event("Standup", at(9), at(9, 30)), Fixture.event("Review", at(9, 30), at(10))]
        #expect(marks(events, gap: 0) == ["Review": "after Standup"])
    }

    @Test func gapEqualToThresholdCounts() {
        let events = [Fixture.event("Standup", at(9), at(9, 30)), Fixture.event("Review", at(9, 35), at(10))]
        #expect(marks(events, gap: 5) == ["Review": "after Standup"])
    }

    @Test func gapLongerThanThresholdDoesNotCount() {
        let events = [Fixture.event("Standup", at(9), at(9, 30)), Fixture.event("Review", at(9, 36), at(10))]
        #expect(marks(events, gap: 5).isEmpty)
        #expect(marks(events, gap: 10) == ["Review": "after Standup"])
    }

    @Test func anyGapFailsTheNoGapThreshold() {
        let events = [Fixture.event("Standup", at(9), at(9, 30)), Fixture.event("Review", at(9, 31), at(10))]
        #expect(marks(events, gap: 0).isEmpty)
    }

    @Test func overlappingMeetingIsMarked() {
        let events = [Fixture.event("Standup", at(9), at(9, 30)), Fixture.event("Review", at(9, 15), at(10))]
        #expect(marks(events) == ["Review": "overlaps Standup"])
    }

    @Test func meetingsStartingTogetherMarkOnlyOne() {
        let events = [Fixture.event("Standup", at(9), at(9, 30)), Fixture.event("Review", at(9), at(10))]
        #expect(marks(events) == ["Review": "overlaps Standup"])
    }

    @Test func chainOfThreeMarksEachAfterItsPredecessor() {
        let events = [
            Fixture.event("C", at(11), at(12)),
            Fixture.event("A", at(9), at(10)),
            Fixture.event("B", at(10), at(11)),
        ]
        #expect(marks(events, gap: 0) == ["B": "after A", "C": "after B"])
    }

    @Test func meetingInsideALongOneOverlapsIt() {
        let events = [
            Fixture.event("Workshop", at(9), at(12)),
            Fixture.event("Call", at(10), at(10, 30)),
            Fixture.event("Sync", at(10, 30), at(11)),
        ]
        #expect(marks(events) == ["Call": "overlaps Workshop", "Sync": "overlaps Workshop"])
    }

    @Test func differentDayIsNotBackToBack() {
        let events = [
            Fixture.event("Late call", at(23), at(23, 58)),
            Fixture.event("Early call", at(0, 2, day: 30), at(0, 30, day: 30)),
        ]
        #expect(marks(events, gap: 5).isEmpty)
    }

    @Test func declinedCancelledAndAllDayEventsAreIgnored() {
        let events = [
            Fixture.event("Holiday", Fixture.date(2026, 9, 29), Fixture.date(2026, 9, 30), allDay: true),
            Fixture.event("Declined", at(9), at(9, 30), declined: true),
            Fixture.event("Cancelled", at(9, 30), at(10), cancelled: true),
            Fixture.event("Review", at(10), at(10, 30)),
            Fixture.event("Skipped", at(10, 30), at(11), declined: true),
        ]
        #expect(marks(events).isEmpty)
    }
}
