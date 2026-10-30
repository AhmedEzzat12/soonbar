import Foundation

public struct MeetingAlertSettings: Sendable, Equatable {
    /// When to alert, in minutes before the start; 0 = when it starts. Each one fires once per meeting.
    public var leadMinutes: [Int]
    /// Only alert for events that have a video-call link.
    public var onlyWithVideoLink: Bool

    public init(leadMinutes: [Int] = [0], onlyWithVideoLink: Bool = false) {
        self.leadMinutes = Array(Set(leadMinutes.filter { $0 >= 0 })).sorted(by: >)
        self.onlyWithVideoLink = onlyWithVideoLink
    }
}

/// What the user has done with alerts so far: which have been shown, which meetings they've joined, and snoozes.
public struct MeetingAlertState: Sendable, Equatable {
    /// Alert moments already shown, as `MeetingAlertPlanner` keys.
    public var shown: Set<String> = []
    /// Meetings joined from an alert: no more alerts for them.
    public var finished: Set<String> = []
    /// One more alert for a meeting at this time ("remind me in 2 minutes").
    public var snoozed: [String: Date] = [:]

    public init() {}

    /// Forgets meetings that are no longer in the calendar.
    public mutating func keep(eventIDs: Set<String>) {
        shown = shown.filter { eventIDs.contains(MeetingAlertPlanner.eventID(ofKey: $0)) }
        finished.formIntersection(eventIDs)
        snoozed = snoozed.filter { eventIDs.contains($0.key) }
    }
}

/// An alert to show now, with the moments it covers (several can fall due together, e.g. after the Mac wakes).
public struct DueMeetingAlert: Sendable, Equatable {
    public let event: CalendarEvent
    public let keys: Set<String>
}

/// Decides when the full-screen meeting alert fires.
public enum MeetingAlertPlanner {
    /// How late an alert may still fire (after sleep, launch, or a slow timer). Later than this,
    /// a full-screen interruption for a meeting already under way is more annoying than useful.
    public static let grace: TimeInterval = 120

    /// Meetings with an alert moment in `(now - grace, now]` not shown yet, in start order.
    public static func dueAlerts(
        events: [CalendarEvent], now: Date, settings: MeetingAlertSettings, state: MeetingAlertState
    ) -> [DueMeetingAlert] {
        candidates(events, now: now, settings: settings, state: state).compactMap { event in
            let keys = moments(for: event, settings: settings, state: state)
                .filter { $0.date <= now && $0.date > now.addingTimeInterval(-grace) }
                .map(\.key)
            return keys.isEmpty ? nil : DueMeetingAlert(event: event, keys: Set(keys))
        }
        .sorted { ($0.event.start, $0.event.title) < ($1.event.start, $1.event.title) }
    }

    /// The next moment after `now` when an alert becomes due, for scheduling a precise timer.
    public static func nextAlertDate(
        events: [CalendarEvent], now: Date, settings: MeetingAlertSettings, state: MeetingAlertState
    ) -> Date? {
        candidates(events, now: now, settings: settings, state: state)
            .flatMap { moments(for: $0, settings: settings, state: state) }
            .map(\.date)
            .filter { $0 > now }
            .min()
    }

    /// When "remind me in N minutes" should alert again, or nil once the meeting would be over by then.
    public static func snoozeDate(for event: CalendarEvent, now: Date, minutes: Int) -> Date? {
        let date = now.addingTimeInterval(TimeInterval(minutes * 60))
        return date < event.end ? date : nil
    }

    /// The meeting's alert moments not shown yet: one per lead time, plus a snooze.
    static func moments(for event: CalendarEvent, settings: MeetingAlertSettings, state: MeetingAlertState) -> [(key: String, date: Date)] {
        var moments = settings.leadMinutes.map { minutes in
            (key: "\(event.id)|lead:\(minutes)", date: event.start.addingTimeInterval(TimeInterval(-minutes * 60)))
        }
        if let snooze = state.snoozed[event.id] {
            moments.append((key: "\(event.id)|snooze:\(Int(snooze.timeIntervalSinceReferenceDate))", date: snooze))
        }
        return moments.filter { !state.shown.contains($0.key) }
    }

    static func eventID(ofKey key: String) -> String {
        key.components(separatedBy: "|").dropLast().joined(separator: "|")
    }

    private static func candidates(
        _ events: [CalendarEvent], now: Date, settings: MeetingAlertSettings, state: MeetingAlertState
    ) -> [CalendarEvent] {
        events.filter { event in
            !event.isAllDay && !event.isCancelled && !event.isDeclined && event.end > now
                && !state.finished.contains(event.id)
                && (!settings.onlyWithVideoLink
                    || MeetingLinkDetector.detect(url: event.url, location: event.location, notes: event.notes) != nil)
        }
    }
}
