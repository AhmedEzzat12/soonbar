import Foundation

public struct WorkingHours: Hashable, Sendable, Codable {
    /// Minutes after midnight.
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    public static let standard = WorkingHours(startMinutes: 9 * 60, endMinutes: 18 * 60)
}

public enum FreeTimeCalculator {
    /// Gaps of at least `minimumMinutes` between `now` and the end of today's working hours.
    public static func freeSlots(
        events: [CalendarEvent], now: Date, workingHours: WorkingHours, minimumMinutes: Int = 30, calendar: Calendar
    ) -> [DateInterval] {
        let dayStart = calendar.startOfDay(for: now)
        guard let workStart = wallClock(workingHours.startMinutes, on: dayStart, calendar: calendar),
              let workEnd = wallClock(workingHours.endMinutes, on: dayStart, calendar: calendar) else { return [] }
        let windowStart = max(now, workStart)
        guard windowStart < workEnd else { return [] }
        return freeSlots(events: events, in: DateInterval(start: windowStart, end: workEnd), minimumMinutes: minimumMinutes)
    }

    /// Gaps of at least `minimumMinutes` inside `window`. Timed events that aren't declined or cancelled
    /// are busy; all-day events are not (holidays, birthdays and "working from home" markers rarely block time).
    public static func freeSlots(events: [CalendarEvent], in window: DateInterval, minimumMinutes: Int) -> [DateInterval] {
        let busy = events
            .filter { !$0.isAllDay && !$0.isCancelled && !$0.isDeclined && $0.end > window.start && $0.start < window.end }
            .map { (start: max($0.start, window.start), end: min($0.end, window.end)) }
            .sorted { $0.start < $1.start }

        var slots: [DateInterval] = []
        var cursor = window.start
        for block in busy {
            if block.start > cursor { slots.append(DateInterval(start: cursor, end: block.start)) }
            cursor = max(cursor, block.end)
        }
        if cursor < window.end { slots.append(DateInterval(start: cursor, end: window.end)) }
        return slots.filter { $0.duration >= TimeInterval(minimumMinutes * 60) }
    }

    /// Wall-clock time on `dayStart` (DST-safe). 24:00 means the next midnight.
    static func wallClock(_ minutes: Int, on dayStart: Date, calendar: Calendar) -> Date? {
        if minutes >= 24 * 60 { return calendar.date(byAdding: .day, value: 1, to: dayStart) }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart)
    }
}
