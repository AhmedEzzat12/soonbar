import Foundation

/// Times in a second time zone, for people who work with someone elsewhere.
public enum SecondTimeZone {
    /// "16:00–17:00 New York", with "(+1)" or "(−1)" when the meeting starts on another day there.
    /// nil for all-day events, and when the zone shows the same wall-clock time as the user's.
    public static func timeRange(for event: CalendarEvent, in zone: TimeZone, calendar: Calendar, locale: Locale) -> String? {
        guard !event.isAllDay, !sameClock(zone, calendar.timeZone, at: event.start) else { return nil }
        let there = calendar.inTimeZone(zone)
        let range = "\(AgendaFormatting.time(event.start, calendar: there, locale: locale))–"
            + AgendaFormatting.time(event.end, calendar: there, locale: locale)
        let shift = dayShift(event.start, from: calendar, to: there)
        let marker = shift == 0 ? "" : " (\(shift > 0 ? "+" : "−")\(abs(shift)))"
        return "\(range)\(marker) \(cityName(zone))"
    }

    /// "New York 03:12" for a header clock.
    public static func clock(now: Date, zone: TimeZone, calendar: Calendar, locale: Locale) -> String {
        "\(cityName(zone)) \(AgendaFormatting.time(now, calendar: calendar.inTimeZone(zone), locale: locale))"
    }

    /// The last part of the identifier with underscores as spaces: "America/New_York" → "New York"; "GMT" stays.
    public static func cityName(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    static func sameClock(_ a: TimeZone, _ b: TimeZone, at date: Date) -> Bool {
        a.secondsFromGMT(for: date) == b.secondsFromGMT(for: date)
    }

    /// How many calendar days `date` is ahead (or behind) in `there` compared to `here`.
    static func dayShift(_ date: Date, from here: Calendar, to there: Calendar) -> Int {
        let fields: Set<Calendar.Component> = [.year, .month, .day]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let local = utc.date(from: here.dateComponents(fields, from: date)),
              let remote = utc.date(from: there.dateComponents(fields, from: date)) else { return 0 }
        return utc.dateComponents([.day], from: local, to: remote).day ?? 0
    }
}

extension Calendar {
    func inTimeZone(_ zone: TimeZone) -> Calendar {
        var copy = self
        copy.timeZone = zone
        return copy
    }
}
