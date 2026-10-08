import Foundation

/// How far ahead the next event may be and still appear in the menu bar.
public enum MenuBarWindow: String, CaseIterable, Codable, Sendable {
    case thirtyMinutes
    case oneHour
    case threeHours
    case restOfToday
    case always
}

public struct MenuBarTitleSettings: Sendable {
    public var window: MenuBarWindow
    public var maxTitleLength: Int
    /// During a meeting, show its time left (and the meeting right after it) instead of the next event.
    public var showMeetingTimeLeft: Bool

    public init(window: MenuBarWindow = .restOfToday, maxTitleLength: Int = 25, showMeetingTimeLeft: Bool = false) {
        self.window = window
        self.maxTitleLength = maxTitleLength
        self.showMeetingTimeLeft = showMeetingTimeLeft
    }
}

public struct MenuBarTitle: Equatable, Sendable {
    public let text: String
    public let event: CalendarEvent
    /// The current meeting is in its last few minutes; only set when showing time left.
    public var isUrgent = false
}

public enum MenuBarTitleFormatter {
    /// An upcoming event closer than this takes priority over an ongoing one.
    static let imminentInterval: TimeInterval = 10 * 60
    /// Time left at or below this makes the title urgent.
    static let urgentInterval: TimeInterval = 5 * 60

    public static func title(
        events: [CalendarEvent], now: Date, settings: MenuBarTitleSettings, calendar: Calendar, locale: Locale
    ) -> MenuBarTitle? {
        let candidates = events.filter { !$0.isAllDay && !$0.isCancelled && !$0.isDeclined && $0.end > now }
        let upcoming = candidates.filter { $0.start > now }.sorted { $0.start < $1.start }
        let ongoing = candidates.filter { $0.start <= now }.sorted { $0.end < $1.end }

        if settings.showMeetingTimeLeft, let current = ongoing.first {
            return timeLeft(in: current, followedBy: upcoming.first, now: now, settings: settings)
        }
        if let next = upcoming.first, next.start.timeIntervalSince(now) <= imminentInterval {
            return make(next, RelativeTime.untilStart(next.start, now: now, calendar: calendar, locale: locale), settings)
        }
        if let current = ongoing.first {
            return make(current, RelativeTime.remaining(until: current.end, now: now), settings)
        }
        if let next = upcoming.first, isWithinWindow(next.start, now: now, window: settings.window, calendar: calendar) {
            return make(next, RelativeTime.untilStart(next.start, now: now, calendar: calendar, locale: locale), settings)
        }
        return nil
    }

    public static func truncate(_ text: String, to maxLength: Int) -> String {
        guard maxLength > 1, text.count > maxLength else { return text }
        return text.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func make(_ event: CalendarEvent, _ relative: String, _ settings: MenuBarTitleSettings) -> MenuBarTitle {
        MenuBarTitle(text: "\(truncate(event.title, to: settings.maxTitleLength)) · \(relative)", event: event)
    }

    /// "Standup · 3m left → Design review" when the next meeting starts before this one ends.
    private static func timeLeft(
        in current: CalendarEvent, followedBy next: CalendarEvent?, now: Date, settings: MenuBarTitleSettings
    ) -> MenuBarTitle {
        var text = "\(truncate(current.title, to: settings.maxTitleLength)) · \(RelativeTime.remaining(until: current.end, now: now))"
        if let next, next.start <= current.end {
            text += " → \(truncate(next.title, to: settings.maxTitleLength))"
        }
        let isUrgent = current.end.timeIntervalSince(now) <= urgentInterval
        return MenuBarTitle(text: text, event: current, isUrgent: isUrgent)
    }

    private static func isWithinWindow(_ start: Date, now: Date, window: MenuBarWindow, calendar: Calendar) -> Bool {
        let seconds = start.timeIntervalSince(now)
        switch window {
        case .thirtyMinutes: return seconds <= 30 * 60
        case .oneHour: return seconds <= 60 * 60
        case .threeHours: return seconds <= 3 * 60 * 60
        case .restOfToday: return calendar.isDate(start, inSameDayAs: now)
        case .always: return true
        }
    }
}
