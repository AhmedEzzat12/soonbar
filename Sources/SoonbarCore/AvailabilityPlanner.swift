import Foundation

public struct AvailabilitySettings: Hashable, Sendable {
    /// Working days to cover, starting today.
    public var workingDays: Int
    public var workingHours: WorkingHours
    /// Shortest free slot worth offering.
    public var minimumMinutes: Int

    public init(workingDays: Int, workingHours: WorkingHours, minimumMinutes: Int) {
        self.workingDays = workingDays
        self.workingHours = workingHours
        self.minimumMinutes = minimumMinutes
    }
}

/// One working day's free time, as offered when sharing availability.
public struct AvailabilityDay: Hashable, Sendable {
    public var day: Date
    /// That day's working hours.
    public var workingHours: DateInterval
    public var slots: [DateInterval]

    public init(day: Date, workingHours: DateInterval, slots: [DateInterval]) {
        self.day = day
        self.workingHours = workingHours
        self.slots = slots
    }

    /// Nothing booked during the whole working day.
    public var isFreeAllDay: Bool { slots == [workingHours] }
}

/// Free time over the next few working days, for answering "when are you free?".
public enum AvailabilityPlanner {
    /// Offered times start on a quarter hour.
    static let stepMinutes = 15

    /// The covered working days (Monday to Friday) with their free slots, including days with none.
    /// Today counts only while some of its working hours are still ahead; it starts at `now` rounded up
    /// to the next quarter hour.
    public static func days(
        events: [CalendarEvent], now: Date, settings: AvailabilitySettings, calendar: Calendar
    ) -> [AvailabilityDay] {
        windows(now: now, settings: settings, calendar: calendar).map { day, hours, offered in
            let slots = FreeTimeCalculator.freeSlots(events: events, in: offered, minimumMinutes: settings.minimumMinutes)
            return AvailabilityDay(day: day, workingHours: hours, slots: slots)
        }
    }

    /// The range to fetch events for: from today until the end of the last covered day.
    public static func interval(now: Date, settings: AvailabilitySettings, calendar: Calendar) -> DateInterval? {
        guard let last = windows(now: now, settings: settings, calendar: calendar).last else { return nil }
        return DateInterval(start: calendar.startOfDay(for: now), end: last.hours.end)
    }

    /// Each covered day's start, its working hours, and the part of them still on offer.
    private static func windows(
        now: Date, settings: AvailabilitySettings, calendar: Calendar
    ) -> [(day: Date, hours: DateInterval, offered: DateInterval)] {
        let today = calendar.startOfDay(for: now)
        let earliest = roundedUp(now, toMinutes: stepMinutes, calendar: calendar)
        var result: [(day: Date, hours: DateInterval, offered: DateInterval)] = []
        var offset = 0
        // A week always holds five working days, so this bound is never the reason the loop stops early.
        while result.count < settings.workingDays, offset < settings.workingDays * 7 + 7 {
            defer { offset += 1 }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today), isWorkingDay(day, calendar: calendar),
                  let start = FreeTimeCalculator.wallClock(settings.workingHours.startMinutes, on: day, calendar: calendar),
                  let end = FreeTimeCalculator.wallClock(settings.workingHours.endMinutes, on: day, calendar: calendar),
                  start < end else { continue }
            let offeredStart = max(start, earliest)
            guard offeredStart < end else { continue }
            result.append((day, DateInterval(start: start, end: end), DateInterval(start: offeredStart, end: end)))
        }
        return result
    }

    /// Monday to Friday (`.weekday` is 1 for Sunday in every Foundation calendar).
    static func isWorkingDay(_ day: Date, calendar: Calendar) -> Bool {
        (2...6).contains(calendar.component(.weekday, from: day))
    }

    /// The next wall-clock multiple of `minutes` at or after `date` (10:07 → 10:15, 10:15 → 10:15).
    static func roundedUp(_ date: Date, toMinutes minutes: Int, calendar: Calendar) -> Date {
        guard let hourStart = calendar.dateInterval(of: .hour, for: date)?.start else { return date }
        let step = TimeInterval(minutes * 60)
        let steps = (date.timeIntervalSince(hourStart) / step).rounded(.up)
        return hourStart.addingTimeInterval(steps * step)
    }
}
