import Foundation

public enum RelativeTime {
    /// "now", "in 45m", "in 2h 15m", "at 17:30" (later today), "Thu 09:00" (another day).
    public static func untilStart(_ start: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds < 60 { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes)m" }
        if minutes < 6 * 60 { return "in \(duration(minutes: minutes))" }
        if calendar.isDate(start, inSameDayAs: now) {
            return "at \(format(start, template: "jmm", calendar: calendar, locale: locale))"
        }
        return format(start, template: "EEEjmm", calendar: calendar, locale: locale)
    }

    /// "8m left", "1h 5m left".
    public static func remaining(until end: Date, now: Date) -> String {
        let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        return "\(duration(minutes: minutes)) left"
    }

    /// "45m", "2h", "2h 15m".
    public static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Formats with a locale-aware template ("jmm" follows the locale's 12/24-hour preference).
    static func format(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let key = [template, locale.identifier, "\(calendar.identifier)", calendar.timeZone.identifier,
                   "\(calendar.firstWeekday)"].joined(separator: "|")
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let formatter = formatters[key] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
        formatters[key] = formatter
        return formatter.string(from: date)
    }

    /// Creating a formatter and resolving its template is costly, and every agenda row formats several dates,
    /// so formatters are kept per template, locale, calendar and time zone.
    private static let formatterLock = NSLock()
    /// Guarded by `formatterLock`; DateFormatter itself is thread-safe for formatting.
    private nonisolated(unsafe) static var formatters: [String: DateFormatter] = [:]

    /// Forgets cached formatters, e.g. when the user changes the 12/24-hour or region setting.
    public static func resetFormatters() {
        formatterLock.lock()
        formatters.removeAll()
        formatterLock.unlock()
    }
}
