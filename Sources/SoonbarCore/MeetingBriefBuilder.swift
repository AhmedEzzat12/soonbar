import Foundation

/// A link worth opening before a meeting, with a short label.
public struct MeetingBriefLink: Hashable, Sendable {
    public let url: URL
    public let title: String
}

/// What the meeting brief shows for one event.
public struct MeetingBrief: Hashable, Sendable {
    /// Sorted and capped; `moreAttendees` counts the rest.
    public var attendees: [Attendee]
    public var moreAttendees: Int
    /// nil when the location is only the meeting link.
    public var location: String?
    /// The event's own URL and links from the notes, minus the meeting link and its provider's pages.
    public var links: [MeetingBriefLink]
    /// The first lines of plain notes, without bare links or invitation boilerplate.
    public var notes: String?
    public var meetingLink: MeetingLink?
}

public enum MeetingBriefBuilder {
    public static func build(
        for event: CalendarEvent, maxAttendees: Int = 8, maxNoteLines: Int = 4, maxLinks: Int = 5
    ) -> MeetingBrief {
        let meetingLink = MeetingLinkDetector.detect(url: event.url, location: event.location, notes: event.notes)
        let meetingDomain = meetingLink.flatMap { domain(of: $0.url) }
        let attendees = sorted(event.attendees)
        // Cap including the "and N more" line, so it never replaces a single name.
        let shown = attendees.count > maxAttendees ? Array(attendees.prefix(maxAttendees - 1)) : attendees
        return MeetingBrief(
            attendees: shown,
            moreAttendees: attendees.count - shown.count,
            location: location(event.location),
            links: Array(links(eventURL: event.url, notes: event.notes ?? "", meetingDomain: meetingDomain).prefix(maxLinks)),
            notes: event.notes.flatMap { trimmedNotes($0, meetingDomain: meetingDomain, maxLines: maxNoteLines) },
            meetingLink: meetingLink
        )
    }

    /// Organizer first, then accepted, tentative, pending (or unknown), declined; by name within each group.
    public static func sorted(_ attendees: [Attendee]) -> [Attendee] {
        func rank(_ attendee: Attendee) -> Int {
            if attendee.isOrganizer { return 0 }
            switch attendee.status {
            case .accepted: return 1
            case .tentative: return 2
            case .pending: return 3
            case .unknown: return 4
            case .declined: return 5
            }
        }
        return attendees.sorted {
            let (left, right) = (rank($0), rank($1))
            if left != right { return left < right }
            return displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending
        }
    }

    /// "You" for the current user, else the name, else the email.
    public static func displayName(_ attendee: Attendee) -> String {
        if attendee.isCurrentUser { return "You" }
        if let name = attendee.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        if let email = attendee.email, !email.isEmpty { return email }
        return "Unknown"
    }

    /// "in 5m" before the start, "now" around it, "started 3m ago" after.
    public static func status(start: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds >= 60 { return RelativeTime.untilStart(start, now: now, calendar: calendar, locale: locale) }
        if seconds > -60 { return "now" }
        return "started \(RelativeTime.duration(minutes: Int(-seconds / 60))) ago"
    }

    // MARK: - Parts

    static func location(_ raw: String?) -> String? {
        guard var text = raw else { return nil }
        for (range, url) in urls(in: text).reversed() where MeetingLinkDetector.classify(url) != nil {
            text.removeSubrange(range)
        }
        text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|")))
        return hasText(text) ? text : nil
    }

    static func links(eventURL: URL?, notes: String, meetingDomain: String?) -> [MeetingBriefLink] {
        let titles = anchorTitles(in: notes)
        var seen = Set<String>()
        var result: [MeetingBriefLink] = []
        for url in [eventURL].compactMap({ $0 }) + urls(in: notes).map(\.1) {
            guard url.host != nil, MeetingLinkDetector.classify(url) == nil,
                  meetingDomain == nil || domain(of: url) != meetingDomain,
                  seen.insert(url.absoluteString).inserted else { continue }
            result.append(MeetingBriefLink(url: url, title: titles[url.absoluteString] ?? shortHost(url)))
        }
        return result
    }

    /// Invitations from Teams and Google Calendar append their join instructions below a separator line;
    /// the agenda, when there is one, comes before it.
    static func trimmedNotes(_ raw: String, meetingDomain: String?, maxLines: Int) -> String? {
        var lines = AgendaFormatting.plainNotes(raw, limit: Int.max)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let isSeparator = { (line: String) in line.count >= 3 && !hasText(line) }
        if let separator = lines.firstIndex(where: isSeparator), lines[..<separator].contains(where: hasText) {
            lines = Array(lines[..<separator])
        }
        lines = lines.filter { line in
            let found = urls(in: line)
            var rest = line
            for (range, _) in found.reversed() { rest.removeSubrange(range) }
            let mentionsMeeting = meetingDomain != nil && found.contains { domain(of: $0.1) == meetingDomain }
            return hasText(rest) && !mentionsMeeting
        }
        guard !lines.isEmpty else { return nil }
        let text = lines.prefix(maxLines).joined(separator: "\n")
        let limit = 300
        if text.count > limit { return String(text.prefix(limit)) + "…" }
        return lines.count > maxLines ? text + "…" : text
    }

    // MARK: - Helpers

    private static func hasText(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    /// http(s) URLs with their ranges, trailing punctuation removed and `&amp;` decoded (HTML notes).
    private static func urls(in text: String) -> [(Range<String.Index>, URL)] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'\)\]]+"#) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard var range = Range(match.range, in: text) else { return nil }
            while range.upperBound > range.lowerBound, ".,;:!?".contains(text[text.index(before: range.upperBound)]) {
                range = range.lowerBound..<text.index(before: range.upperBound)
            }
            let candidate = String(text[range]).replacingOccurrences(of: "&amp;", with: "&")
            return URL(string: candidate).map { (range, $0) }
        }
    }

    /// `<a href="url">text</a>` → [url: text], skipping anchors whose text is just the address.
    private static func anchorTitles(in notes: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [:] }
        var titles: [String: String] = [:]
        for match in regex.matches(in: notes, range: NSRange(notes.startIndex..., in: notes)) {
            guard let hrefRange = Range(match.range(at: 1), in: notes),
                  let textRange = Range(match.range(at: 2), in: notes) else { continue }
            let href = String(notes[hrefRange]).replacingOccurrences(of: "&amp;", with: "&")
            let title = AgendaFormatting.plainNotes(String(notes[textRange]), limit: 60)
                .components(separatedBy: .newlines).joined(separator: " ")
            guard let url = URL(string: href), hasText(title), !title.lowercased().hasPrefix("http") else { continue }
            titles[url.absoluteString] = titles[url.absoluteString] ?? title
        }
        return titles
    }

    private static func shortHost(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The last two host labels ("acme.zoom.us" → "zoom.us"); enough for the meeting providers we detect.
    private static func domain(of url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.split(separator: ".").suffix(2).joined(separator: ".")
    }
}
