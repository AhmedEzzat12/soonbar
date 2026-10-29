import Foundation

/// An event or reminder found in pasted text, with its date still as written.
public struct TextImportCandidate: Sendable, Equatable {
    public var title: String
    public var kind: QuickAddKind
    /// The date and time as the text gives them ("next Tuesday at 3pm"); nil when it gives none.
    public var when: String?
    public var location: String?

    public init(title: String, kind: QuickAddKind, when: String? = nil, location: String? = nil) {
        self.title = title
        self.kind = kind
        self.when = when
        self.location = location
    }
}

/// A candidate ready to preview, its date resolved the same way quick add resolves one.
public struct TextImportItem: Identifiable, Sendable, Equatable {
    public let id: Int
    public var title: String
    public var kind: QuickAddKind
    public var location: String?
    public var isAllDay: Bool
    public var start: Date
    public var end: Date
    /// Reminders only: whether the due date has a time of day.
    public var hasDueTime: Bool
    /// False when the text gave no date that could be trusted; the preview then asks for one.
    public var hasDate: Bool

    public init(id: Int, title: String, kind: QuickAddKind, location: String?, isAllDay: Bool, start: Date, end: Date,
                hasDueTime: Bool, hasDate: Bool) {
        self.id = id
        self.title = title
        self.kind = kind
        self.location = location
        self.isAllDay = isAllDay
        self.start = start
        self.end = end
        self.hasDueTime = hasDueTime
        self.hasDate = hasDate
    }
}

/// Turns pasted text into events and reminders to preview. Whatever finds the candidates (a language model or plain
/// date detection), dates are only taken from the text itself and are resolved by `QuickAddParser`.
public enum TextImport {
    /// True when every number, time, month, weekday and relative day word in `phrase` also appears in `text`, close
    /// together. Rejects dates a language model calculated or made up ("Friday 11:00" for a text that said "tomorrow
    /// 11" and mentioned Friday elsewhere), while accepting harmless rewording ("Oct 30, 7:30pm" for "Friday Oct 30 at
    /// 7:30 pm").
    public static func isGrounded(_ phrase: String, in text: String) -> Bool {
        let wanted = significantTokens(phrase)
        guard !wanted.isEmpty else { return false }
        let words = tokens(text)
        let window = max(8, wanted.count * 4)
        for start in words.indices where wanted.contains(words[start]) {
            var seen = Set<String>()
            for word in words[start..<min(words.count, start + window)] where wanted.contains(word) {
                seen.insert(word)
                if seen.count == wanted.count { return true }
            }
        }
        return false
    }

    /// Resolves each candidate's date. Ungrounded or unreadable dates leave the item without one, for the user to set.
    public static func items(from candidates: [TextImportCandidate], sourceText: String, parser: QuickAddParser) -> [TextImportItem] {
        candidates.enumerated().compactMap { index, candidate in
            let title = QuickAddParser.cleanTitle(QuickAddParser.collapsingWhitespace(candidate.title))
            guard !title.isEmpty else { return nil }
            let phrase = candidate.when.map(QuickAddParser.collapsingWhitespace) ?? ""
            let trusted = !phrase.isEmpty && isGrounded(phrase, in: sourceText)
            // Parse the phrase on its own, so title words can't be mistaken for dates.
            let draft = parser.parse(trusted ? "x \(phrase)" : "x", calendars: [], forcedKind: candidate.kind)
            return TextImportItem(
                id: index, title: title, kind: candidate.kind,
                location: candidate.location.map(QuickAddParser.collapsingWhitespace).flatMap { $0.isEmpty ? nil : $0 },
                isAllDay: draft.isAllDay, start: draft.start, end: draft.end, hasDueTime: draft.hasDueTime,
                hasDate: trusted && draft.hasExplicitDate
            )
        }
    }

    /// Without a language model: every sentence that contains a date becomes an event, titled with the rest of the
    /// sentence. Sentences that start like a to-do ("remind me to …", "don't forget …") become reminders.
    public static func candidatesWithoutModel(in text: String) -> [TextImportCandidate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        var candidates: [TextImportCandidate] = []
        (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length), options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            let ns = sentence as NSString
            guard let match = detector.firstMatch(in: sentence, range: NSRange(location: 0, length: ns.length)) else { return }
            var rest = QuickAddParser.removing(match.range, from: sentence)
            var kind = QuickAddKind.event
            for prefix in todoPrefixes where rest.lowercased().hasPrefix(prefix) {
                kind = .reminder
                rest = String(rest.dropFirst(prefix.count))
                break
            }
            rest = rest.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            let title = rest.count > 80 ? String(rest.prefix(80)).trimmingCharacters(in: .whitespaces) + "…" : rest
            candidates.append(TextImportCandidate(title: title, kind: kind, when: ns.substring(with: match.range)))
        }
        return candidates
    }

    static let todoPrefixes = ["remind me to ", "reminder to ", "don't forget to ", "don’t forget to ", "don't forget ", "don’t forget ", "todo: ", "to do: "]

    // MARK: - Tokens

    /// Words that carry date meaning; everything else in a phrase ("at", "on", "the") is ignored when grounding.
    static let dateWords: Set<String> = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
        "mon", "tue", "wed", "thu", "fri", "sat", "sun",
        "today", "tonight", "tomorrow", "yesterday", "week", "weekend", "noon", "midnight",
        "morning", "afternoon", "evening",
    ]
    // Not counted: "next"/"this" and am/pm, which a model adds when rewording ("next Tuesday" for "Tuesday",
    // "3pm" for "at 3") without changing the date the parser then reads.

    static func significantTokens(_ phrase: String) -> Set<String> {
        Set(tokens(phrase).filter { $0.first?.isNumber == true || dateWords.contains($0) })
    }

    /// Lowercased tokens with months and weekdays cut to three letters, "09:00" and "9:00" alike, and "11:00" as "11",
    /// so the same time written two ways compares equal.
    static func tokens(_ text: String) -> [String] {
        let lower = text.lowercased()
        let pattern = #"\d{1,2}:\d{2}|\d+|[a-z]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)).compactMap { match in
            guard let range = Range(match.range, in: lower) else { return nil }
            var token = String(lower[range])
            if token.first?.isNumber == true {
                if token.hasSuffix(":00") { token.removeLast(3) }
                while token.count > 1, token.hasPrefix("0"), !token.hasPrefix("0:") { token.removeFirst() }
                return token
            }
            return nameAbbreviations[token] ?? token
        }
    }

    /// Full and common short names only, so "mark" or "friend" never read as March or Friday.
    private static let nameAbbreviations: [String: String] = {
        var map: [String: String] = [:]
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for name in months + days { map[name] = String(name.prefix(3)) }
        for (short, abbreviation) in [("sept", "sep"), ("tues", "tue"), ("weds", "wed"), ("thur", "thu"), ("thurs", "thu")] {
            map[short] = abbreviation
        }
        return map
    }()
}
