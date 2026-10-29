import Foundation

public enum QuickAddKind: String, CaseIterable, Hashable, Sendable {
    case event
    case reminder

    public var calendarKind: CalendarKind { self == .event ? .events : .reminders }
}

public struct QuickAddDraft: Equatable, Sendable {
    public var kind: QuickAddKind
    public var title: String
    /// Calendar (events) or list (reminders) chosen with `#token`; nil means "use the default".
    public var calendarID: String?
    public var unmatchedCalendarToken: String?
    public var isAllDay: Bool
    /// Event start, or reminder due date.
    public var start: Date
    public var end: Date
    public var hasDueTime: Bool
    public var hasExplicitDate: Bool

    /// All-day events are saved as one whole day (midnight to the next midnight), whatever time or
    /// seconds-based length the date pickers left behind.
    public func normalized(calendar: Calendar) -> QuickAddDraft {
        guard kind == .event, isAllDay else { return self }
        var copy = self
        copy.start = calendar.startOfDay(for: start)
        copy.end = calendar.date(byAdding: .day, value: 1, to: copy.start) ?? copy.start
        return copy
    }
}

/// Parses "Lunch with Sara tomorrow 1pm 1h #work" or "!Pay rent friday".
/// Rules: leading "!" = reminder; "#token" = calendar/list; "45m" / "1h30m" / "for 2 hours" = duration;
/// dates and times via NSDataDetector. Whatever is left is the title.
public struct QuickAddParser {
    public let calendar: Calendar
    public let now: Date
    public var defaultDurationMinutes = 30

    public init(calendar: Calendar, now: Date) {
        self.calendar = calendar
        self.now = now
    }

    static let hashtagPattern = #"(?:^|\s)#([\p{L}\p{N}_-]+)"#
    static let durationPattern = #"(?i)(?:\bfor\s+)?\b(?:(\d+(?:\.\d+)?)\s*(?:hours|hour|hrs|hr|h)(?:\s*(\d+)\s*(?:minutes|minute|mins|min|m))?|(\d+)\s*(?:minutes|minute|mins|min|m))\b"#
    static let clockTimePattern = #"(?i)\b\d{1,2}(:\d{2})?\s?(am|pm)\b|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b|\bat\s+\d{1,2}\b"#

    public func parse(_ input: String, calendars: [CalendarInfo], forcedKind: QuickAddKind? = nil) -> QuickAddDraft {
        var text = Self.collapsingWhitespace(input)
        var kind = QuickAddKind.event
        if text.hasPrefix("!") {
            kind = .reminder
            text = Self.collapsingWhitespace(String(text.dropFirst()))
        }
        if let forcedKind { kind = forcedKind }

        var calendarID: String?
        var unmatchedToken: String?
        if let match = Self.firstMatch(Self.hashtagPattern, in: text), let token = Self.group(1, of: match, in: text) {
            let targets = calendars.filter { $0.kind == kind.calendarKind && $0.isWritable }
            if let target = Self.matchCalendar(token, in: targets) {
                calendarID = target.id
            } else {
                unmatchedToken = token
            }
            text = Self.removing(match.range, from: text)
        }

        var durationMinutes: Int?
        if kind == .event, let match = Self.firstMatch(Self.durationPattern, in: text) {
            let hours = Self.group(1, of: match, in: text).flatMap(Double.init) ?? 0
            let extraMinutes = Self.group(2, of: match, in: text).flatMap(Int.init) ?? 0
            let minutes = Self.group(3, of: match, in: text).flatMap(Int.init) ?? 0
            let total = Int((hours * 60).rounded()) + extraMinutes + minutes
            if total > 0 {
                durationMinutes = total
                text = Self.removing(match.range, from: text)
            }
        }

        let detected = detectDate(in: text)
        if let detected { text = Self.removing(detected.range, from: text) }

        var draft = QuickAddDraft(
            kind: kind, title: Self.cleanTitle(text), calendarID: calendarID, unmatchedCalendarToken: unmatchedToken,
            isAllDay: false, start: now, end: now, hasDueTime: false, hasExplicitDate: detected != nil
        )
        let duration = TimeInterval((durationMinutes ?? defaultDurationMinutes) * 60)
        switch (kind, detected) {
        case (.event, .some(let found)) where found.hasTime:
            draft.start = found.date
            draft.end = found.date.addingTimeInterval(found.duration > 0 ? found.duration : duration)
        case (.event, .some(let found)):
            draft.isAllDay = true
            draft.start = calendar.startOfDay(for: found.date)
            draft.end = calendar.date(byAdding: .day, value: 1, to: draft.start) ?? draft.start
        case (.event, .none):
            draft.start = nextHalfHour()
            draft.end = draft.start.addingTimeInterval(duration)
        case (.reminder, .some(let found)):
            draft.hasDueTime = found.hasTime
            draft.start = found.hasTime ? found.date : calendar.startOfDay(for: found.date)
            draft.end = draft.start
        case (.reminder, .none):
            draft.start = calendar.startOfDay(for: now)
            draft.end = draft.start
        }
        return draft
    }

    // MARK: - Dates

    struct DetectedDate {
        let range: NSRange
        let date: Date
        let duration: TimeInterval
        let hasTime: Bool
    }

    func detectDate(in text: String) -> DetectedDate? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = text as NSString
        guard let match = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let date = match.date else { return weekPhrase(in: text) }
        let hasTime = Self.containsClockTime(ns.substring(with: match.range))

        func isDateWord(_ word: String) -> Bool {
            detector.firstMatch(in: word, range: NSRange(location: 0, length: (word as NSString).length)) != nil
        }
        // True when `candidate` on its own is entirely a date phrase with the same meaning.
        func meansSame(_ candidate: NSRange) -> Bool {
            let phrase = ns.substring(with: candidate)
            let length = (phrase as NSString).length
            guard let other = detector.firstMatch(in: phrase, range: NSRange(location: 0, length: length)),
                  other.range.location == 0, other.range.length == length, let otherDate = other.date else { return false }
            return hasTime
                ? otherDate == date && other.duration == match.duration
                : calendar.isDate(otherDate, inSameDayAs: date)
        }

        // NSDataDetector sometimes swallows neighbouring title words ("Dinner friday 7pm").
        // Peel non-date words off both edges while the rest still means the same date.
        // "next" and "this" belong to the date ("next Tuesday") even though the date reads the same without them.
        var range = match.range
        while let next = Self.peel(range, in: ns, fromStart: true), !isDateWord(next.word),
              !Self.dateQualifiers.contains(next.word.lowercased()), meansSame(next.rest) {
            range = next.rest
        }
        while let next = Self.peel(range, in: ns, fromStart: false), !isDateWord(next.word), meansSame(next.rest) {
            range = next.rest
        }
        let found = DetectedDate(range: range, date: date, duration: match.duration, hasTime: hasTime)
        guard !hasTime else { return found }
        return weekdayAndHour(found, in: ns) ?? bareHour(after: found, in: ns) ?? found
    }

    static let dateQualifiers: Set<String> = ["next", "this", "coming"]

    /// "tomorrow 11" or "friday 3 with Sam": a bare hour right after a date that has no time. The number must end the
    /// text or come before a joining word, so "tomorrow 12 boxes" stays a count.
    func bareHour(after found: DetectedDate, in text: NSString) -> DetectedDate? {
        let tail = NSRange(location: found.range.location + found.range.length, length: text.length - found.range.location - found.range.length)
        let pattern = #"^\s+(\d{1,2})(?=\s*$|\s*[,.;!?]|\s+(?:for|with|at|in|to|and|on)\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text as String, range: tail),
              let number = Int(text.substring(with: match.range(at: 1))), (1...23).contains(number),
              let date = calendar.date(bySettingHour: Self.hour(fromBare: number), minute: 0, second: 0, of: found.date)
        else { return nil }
        let range = NSRange(location: found.range.location, length: match.range.location + match.range.length - found.range.location)
        return DetectedDate(range: range, date: date, duration: 0, hasTime: true)
    }

    /// The system reads "friday 9" as "Friday the 9th", which can be weeks in the past. A past date written as a weekday and
    /// a small number means that weekday at that hour.
    func weekdayAndHour(_ found: DetectedDate, in text: NSString) -> DetectedDate? {
        let phrase = text.substring(with: found.range)
        guard found.date < calendar.startOfDay(for: now),
              let match = Self.firstMatch(#"(?i)^([a-z]+)\s+(\d{1,2})$"#, in: phrase),
              let word = Self.group(1, of: match, in: phrase), let numberText = Self.group(2, of: match, in: phrase),
              let number = Int(numberText), (1...23).contains(number),
              let weekday = Self.weekday(named: word),
              let day = calendar.nextDate(after: calendar.startOfDay(for: now).addingTimeInterval(-1),
                                          matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime),
              let date = calendar.date(bySettingHour: Self.hour(fromBare: number), minute: 0, second: 0, of: day)
        else { return nil }
        return DetectedDate(range: found.range, date: date, duration: 0, hasTime: true)
    }

    /// Hours written without am/pm: 1–6 mean the afternoon (meetings are rarely at 3 am), 7–12 the morning or noon.
    static func hour(fromBare number: Int) -> Int { number <= 6 ? number + 12 : number }

    /// Calendar weekday (1 = Sunday) for an English day name or its first three letters.
    static func weekday(named word: String) -> Int? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let lower = word.lowercased()
        guard lower.count >= 3 else { return nil }
        return names.firstIndex { $0.hasPrefix(lower) || lower.hasPrefix($0) }.map { $0 + 1 }
    }

    /// Week phrases the system doesn't read: "this week" / "end of the week" (Friday, or today at the weekend),
    /// "next week" (next Monday) and "this weekend" / "the weekend" (Saturday, or today at the weekend). Date only.
    /// "next weekend" is left alone: people disagree on whether it means this coming weekend or the one after.
    func weekPhrase(in text: String) -> DetectedDate? {
        let pattern = #"(?i)\b(?:this\s+week(?!end)|end\s+of\s+(?:the\s+)?week|next\s+week(?!end)|(?<!next\s)(?:this\s+|the\s+)?weekend)\b"#
        guard let match = Self.firstMatch(pattern, in: text) else { return nil }
        let phrase = (text as NSString).substring(with: match.range).lowercased()
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let isWeekend = weekday == 1 || weekday == 7
        func next(_ target: Int) -> Date? {
            calendar.nextDate(after: today.addingTimeInterval(-1), matching: DateComponents(weekday: target), matchingPolicy: .nextTime)
        }
        let date: Date?
        if phrase.hasPrefix("next") {
            date = calendar.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)
        } else if phrase.hasSuffix("weekend") {
            date = isWeekend ? today : next(7)
        } else {
            date = isWeekend ? today : next(6)
        }
        guard let date else { return nil }
        return DetectedDate(range: match.range, date: date, duration: 0, hasTime: false)
    }

    /// Splits the first (or last) word off `range`; nil when `range` is a single word.
    static func peel(_ range: NSRange, in text: NSString, fromStart: Bool) -> (word: String, rest: NSRange)? {
        let phrase = text.substring(with: range) as NSString
        let space = fromStart ? phrase.range(of: " ") : phrase.range(of: " ", options: .backwards)
        guard space.location != NSNotFound else { return nil }
        if fromStart {
            return (phrase.substring(to: space.location),
                    NSRange(location: range.location + space.location + 1, length: range.length - space.location - 1))
        }
        return (phrase.substring(from: space.location + 1), NSRange(location: range.location, length: space.location))
    }

    static func containsClockTime(_ text: String) -> Bool {
        text.range(of: clockTimePattern, options: .regularExpression) != nil
    }

    func nextHalfHour() -> Date {
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let minute = calendar.component(.minute, from: now)
        return calendar.date(byAdding: .minute, value: minute < 30 ? 30 : 60, to: hourStart) ?? now
    }

    // MARK: - Calendars

    /// Exact title match, then prefix, then substring; spaces and case ignored.
    static func matchCalendar(_ token: String, in calendars: [CalendarInfo]) -> CalendarInfo? {
        let wanted = normalize(token)
        let named = calendars.map { (calendar: $0, name: normalize($0.title)) }
        return named.first { $0.name == wanted }?.calendar
            ?? named.first { $0.name.hasPrefix(wanted) }?.calendar
            ?? named.first { $0.name.contains(wanted) }?.calendar
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    // MARK: - Text helpers

    static func cleanTitle(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        let dangling: Set<String> = ["at", "on", "by", "from", "for", "to", "@", "-", "–"]
        while let last = words.last, dangling.contains(last.lowercased()) { words.removeLast() }
        return words.joined(separator: " ")
    }

    static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    static func removing(_ range: NSRange, from text: String) -> String {
        collapsingWhitespace((text as NSString).replacingCharacters(in: range, with: " "))
    }
}
