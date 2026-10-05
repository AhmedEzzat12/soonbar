import Foundation

/// Free times as plain text, one line per day, ready to paste into a chat or email:
///
///     Tue 6 Oct: 10:00–11:30, 14:00–17:00
///     Wed 7 Oct: free all day (09:00–18:00)
///     (times in CEST)
public enum AvailabilityFormatter {
    /// nil when no day has free time. Times are in `calendar.timeZone`.
    public static func text(
        _ days: [AvailabilityDay], includeTimeZone: Bool, calendar: Calendar, locale: Locale
    ) -> String? {
        let free = days.filter { !$0.slots.isEmpty }
        guard let first = free.first else { return nil }
        var lines = free.map { day in
            let date = AgendaFormatting.shortDate(day.day, calendar: calendar, locale: locale)
            let times = day.isFreeAllDay
                ? "free all day (\(range(day.workingHours, calendar: calendar, locale: locale)))"
                : day.slots.map { range($0, calendar: calendar, locale: locale) }.joined(separator: ", ")
            return "\(date): \(times)"
        }
        if includeTimeZone {
            lines.append("(times in \(timeZoneName(calendar.timeZone, at: first.workingHours.start, locale: locale)))")
        }
        return lines.joined(separator: "\n")
    }

    /// The zone's short name at `date`, such as "CEST" in summer and "CET" in winter.
    static func timeZoneName(_ timeZone: TimeZone, at date: Date, locale: Locale) -> String {
        let style: NSTimeZone.NameStyle = timeZone.isDaylightSavingTime(for: date) ? .shortDaylightSaving : .shortStandard
        return timeZone.localizedName(for: style, locale: locale) ?? timeZone.identifier
    }

    private static func range(_ interval: DateInterval, calendar: Calendar, locale: Locale) -> String {
        let start = AgendaFormatting.time(interval.start, calendar: calendar, locale: locale)
        let end = AgendaFormatting.time(interval.end, calendar: calendar, locale: locale)
        return "\(start)–\(end)"
    }
}
