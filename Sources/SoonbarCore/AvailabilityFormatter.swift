import Foundation

/// Free times as plain text, one line per day, ready to paste into a chat or email:
///
///     Tue 6 Oct: 10:00–11:30, 14:00–17:00
///     Wed 7 Oct: free all day (09:00–18:00)
///     (times in CEST)
public enum AvailabilityFormatter {
    /// nil when no day has free time. Times are in `calendar.timeZone`, or in `displayTimeZone` when given:
    /// then slots are regrouped by that zone's dates, so the other person reads their own days and times.
    public static func text(
        _ days: [AvailabilityDay], includeTimeZone: Bool, calendar: Calendar, locale: Locale, displayTimeZone: TimeZone? = nil
    ) -> String? {
        let free = days.filter { !$0.slots.isEmpty }
        guard let first = free.first else { return nil }
        if let zone = displayTimeZone, zone.secondsFromGMT(for: first.workingHours.start) != calendar.timeZone.secondsFromGMT(for: first.workingHours.start) {
            return regroupedText(free, includeTimeZone: includeTimeZone, calendar: calendar.inTimeZone(zone), locale: locale)
        }
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

    /// Lines by the other zone's dates; "free all day" is dropped because it describes the user's working day.
    private static func regroupedText(
        _ free: [AvailabilityDay], includeTimeZone: Bool, calendar there: Calendar, locale: Locale
    ) -> String {
        let slots = free.flatMap(\.slots).sorted { $0.start < $1.start }
        var order: [Date] = []
        var byDay: [Date: [DateInterval]] = [:]
        for slot in slots {
            let day = there.startOfDay(for: slot.start)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(slot)
        }
        var lines = order.map { day in
            let times = (byDay[day] ?? []).map { range($0, calendar: there, locale: locale) }.joined(separator: ", ")
            return "\(AgendaFormatting.shortDate(day, calendar: there, locale: locale)): \(times)"
        }
        // A city reads better than "GMT-4" for the person receiving it.
        if includeTimeZone {
            lines.append("(\(SecondTimeZone.cityName(there.timeZone)) time)")
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
