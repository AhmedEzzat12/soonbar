import Foundation

/// The meeting a back-to-back meeting follows.
public struct BackToBackLink: Equatable, Sendable {
    public let previousTitle: String
    /// The previous meeting is still running when this one starts.
    public let overlaps: Bool

    public init(previousTitle: String, overlaps: Bool) {
        self.previousTitle = previousTitle
        self.overlaps = overlaps
    }
}

/// Finds timed meetings that start with no real break: within `gapMinutes` after another meeting
/// ends on the same day, or while another is still running.
public enum BackToBackDetector {
    /// Event id → the meeting it follows. When several qualify, the one ending last wins, so a meeting
    /// inside a long one reads "overlaps <long one>".
    public static func predecessors(events: [CalendarEvent], gapMinutes: Int, calendar: Calendar) -> [String: BackToBackLink] {
        let meetings = events
            .filter { !$0.isAllDay && !$0.isCancelled && !$0.isDeclined }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        let maxGap = TimeInterval(max(0, gapMinutes) * 60)
        var result: [String: BackToBackLink] = [:]

        for (index, meeting) in meetings.enumerated() {
            let previous = meetings[..<index]
                .filter { earlier in
                    let gap = meeting.start.timeIntervalSince(earlier.end)
                    return gap <= maxGap && (gap < 0 || calendar.isDate(earlier.end, inSameDayAs: meeting.start))
                }
                .max { $0.end < $1.end }
            if let previous {
                result[meeting.id] = BackToBackLink(previousTitle: previous.title, overlaps: previous.end > meeting.start)
            }
        }
        return result
    }
}
