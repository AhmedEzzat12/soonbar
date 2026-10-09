import Foundation

public extension CalendarEvent {
    /// The current user's reply when they are invited (not organizing); nil for their own events.
    var myResponse: Attendee.Status? {
        attendees.first { $0.isCurrentUser && !$0.isOrganizer }?.status
    }
}

/// Invitations the user hasn't settled yet.
public enum InviteStatus {
    /// Upcoming or ongoing invitations still waiting for a reply, counting a recurring series once.
    public static func awaitingReply(events: [CalendarEvent], now: Date) -> [CalendarEvent] {
        var seen = Set<String>()
        return events
            .filter { $0.end > now && !$0.isCancelled && $0.myResponse == .pending }
            .sorted { $0.start < $1.start }
            .filter { seen.insert($0.eventIdentifier).inserted }
    }

    /// Not a firm yes: still unanswered, or answered "maybe".
    public static func isUnconfirmed(_ event: CalendarEvent) -> Bool {
        event.myResponse == .pending || event.myResponse == .tentative
    }
}
