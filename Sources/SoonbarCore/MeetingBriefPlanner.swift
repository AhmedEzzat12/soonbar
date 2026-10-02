import Foundation

public struct MeetingBriefSettings: Sendable, Equatable {
    /// Minutes before the start when the brief appears.
    public var leadMinutes: Int
    /// Skip events where nobody but the current user is invited.
    public var onlyWithAttendees: Bool

    public init(leadMinutes: Int = 5, onlyWithAttendees: Bool = false) {
        self.leadMinutes = leadMinutes
        self.onlyWithAttendees = onlyWithAttendees
    }
}

/// Decides when the meeting brief appears and goes away.
public enum MeetingBriefPlanner {
    /// The brief stays up this long after the start, so it can still be read (and joined from) when running late.
    public static let lingerAfterStart: TimeInterval = 120

    /// Events whose brief moment has passed and whose start was less than `lingerAfterStart` ago, in start order.
    public static func dueBriefs(
        events: [CalendarEvent], now: Date, settings: MeetingBriefSettings, alreadyBriefed: Set<String>
    ) -> [CalendarEvent] {
        events
            .filter { qualifies($0, settings: settings) && !alreadyBriefed.contains($0.id) }
            .filter { briefDate(for: $0, settings) <= now && dismissDate(for: $0) > now }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// The next moment after `now` when a brief becomes due, for scheduling a precise timer.
    public static func nextBriefDate(
        events: [CalendarEvent], now: Date, settings: MeetingBriefSettings, alreadyBriefed: Set<String>
    ) -> Date? {
        events
            .filter { qualifies($0, settings: settings) && !alreadyBriefed.contains($0.id) }
            .map { briefDate(for: $0, settings) }
            .filter { $0 > now }
            .min()
    }

    /// The first meeting that hasn't ended and would get a brief, for previewing.
    public static func nextMeeting(events: [CalendarEvent], now: Date, settings: MeetingBriefSettings) -> CalendarEvent? {
        events
            .filter { qualifies($0, settings: settings) && $0.end > now }
            .min { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    public static func dismissDate(for event: CalendarEvent) -> Date {
        event.start.addingTimeInterval(lingerAfterStart)
    }

    static func briefDate(for event: CalendarEvent, _ settings: MeetingBriefSettings) -> Date {
        event.start.addingTimeInterval(TimeInterval(-settings.leadMinutes * 60))
    }

    static func qualifies(_ event: CalendarEvent, settings: MeetingBriefSettings) -> Bool {
        !event.isAllDay && !event.isCancelled && !event.isDeclined
            && (!settings.onlyWithAttendees || event.attendees.contains { !$0.isCurrentUser })
    }
}
