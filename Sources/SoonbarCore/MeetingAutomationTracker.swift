import Foundation

public struct MeetingAutomationSettings: Sendable, Equatable {
    public var isEnabled: Bool
    /// Only events with a video-call link count as meetings.
    public var onlyWithVideoLink: Bool

    public init(isEnabled: Bool, onlyWithVideoLink: Bool = false) {
        self.isEnabled = isEnabled
        self.onlyWithVideoLink = onlyWithVideoLink
    }
}

public enum MeetingAutomationAction: Sendable, Equatable {
    /// Run the "meeting started" Shortcut.
    case start
    /// Run the "meeting ended" Shortcut.
    case end
}

/// Decides when the meeting start/end Shortcuts run. Back-to-back and overlapping meetings form one
/// block, so they run once around the whole block rather than between meetings.
public enum MeetingAutomationTracker {
    /// How late a start may still run, and how long after a block ends its end still counts as just now
    /// (after sleep or a slow timer). Older transitions are skipped.
    public static let grace: TimeInterval = 300

    /// A continuous stretch of meetings.
    public struct Block: Sendable, Equatable {
        public var start: Date
        public var end: Date
        /// The start Shortcut ran for this block; its end then always runs, even when noticed late.
        public var startRan: Bool

        public init(start: Date, end: Date, startRan: Bool) {
            self.start = start
            self.end = end
            self.startRan = startRan
        }
    }

    public enum State: Sendable, Equatable {
        case idle
        case inMeeting(Block)
    }

    /// `previous` is nil before the first evaluation (launch, or the feature just turned on): a meeting
    /// already under way is then joined silently, and its end still runs if noticed on time.
    /// Turning the feature off returns nil without running anything.
    public static func evaluate(
        previous: State?, events: [CalendarEvent], now: Date, settings: MeetingAutomationSettings
    ) -> (actions: [MeetingAutomationAction], state: State?) {
        guard settings.isEnabled else { return ([], nil) }
        let current = block(containing: now, events: events, settings: settings)
        guard let previous else {
            return ([], current.map { .inMeeting(Block(start: $0.start, end: $0.end, startRan: false)) } ?? .idle)
        }

        var actions: [MeetingAutomationAction] = []
        if case .inMeeting(let old) = previous {
            // Same block, possibly edited (extended, shortened, or joined by a back-to-back meeting).
            if let current, current.start <= old.end {
                return ([], .inMeeting(Block(start: current.start, end: current.end, startRan: old.startRan)))
            }
            // A block joined silently only ends if that's noticed on time, so waking hours later
            // doesn't run an end the user never had a start for.
            if old.startRan || now < old.end.addingTimeInterval(grace) { actions.append(.end) }
        }
        guard let current else { return (actions, .idle) }
        let fresh = now.timeIntervalSince(current.start) <= grace
        if fresh { actions.append(.start) }
        return (actions, .inMeeting(Block(start: current.start, end: current.end, startRan: fresh)))
    }

    /// The merged span of touching or overlapping meetings that contains `now`.
    static func block(
        containing now: Date, events: [CalendarEvent], settings: MeetingAutomationSettings
    ) -> DateInterval? {
        let spans = events
            .filter { isMeeting($0, settings) }
            .map { (start: $0.start, end: $0.end) }
            .sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for span in spans {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1].end = max(last.end, span.end)
            } else {
                merged.append(span)
            }
        }
        return merged.first { $0.start <= now && now < $0.end }.map { DateInterval(start: $0.start, end: $0.end) }
    }

    static func isMeeting(_ event: CalendarEvent, _ settings: MeetingAutomationSettings) -> Bool {
        !event.isAllDay && !event.isCancelled && !event.isDeclined && event.end > event.start
            && (!settings.onlyWithVideoLink
                || MeetingLinkDetector.detect(url: event.url, location: event.location, notes: event.notes) != nil)
    }
}
