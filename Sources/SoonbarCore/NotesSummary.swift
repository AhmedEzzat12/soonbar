import Foundation

/// A short summary of a meeting invitation's notes, as shown in the meeting brief.
public struct NotesSummary: Sendable, Equatable {
    /// What the meeting is for, in a sentence.
    public var gist: String
    public var agenda: [String]
    /// What the reader is asked to prepare or do.
    public var asks: [String]

    public init(gist: String, agenda: [String], asks: [String]) {
        self.gist = gist
        self.agenda = agenda
        self.asks = asks
    }
}

/// Prepares invitation notes for summarizing: plain text without links, dial-in details and the other boilerplate
/// calendar servers add, so the model reads what the organizer wrote and the text fits its small context.
public enum NotesSummaryInput {
    /// The cleaned notes, or nil when what's left is short enough to read as it is.
    public static func text(from rawNotes: String?, minimumLength: Int = 400, maximumLength: Int = 4_000) -> String? {
        guard let rawNotes else { return nil }
        let lines = AgendaFormatting.plainNotes(rawNotes, limit: Int.max)
            .components(separatedBy: .newlines)
            .map(withoutLinks)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in line.contains { $0.isLetter } && !isBoilerplate(line) }
        let text = lines.joined(separator: "\n")
        guard text.count >= minimumLength else { return nil }
        return text.count > maximumLength ? String(text.prefix(maximumLength)) : text
    }

    /// Lines calendar servers add to every invitation (Teams, Zoom, Meet, Webex dial-ins and footers).
    static let boilerplate = [
        "meeting id", "passcode", "password:", "dial-in", "dial in", "dial by your location", "join by phone",
        "join microsoft teams", "microsoft teams meeting", "join zoom", "zoom meeting", "join with google meet",
        "join on your computer", "click here to join", "one tap mobile", "find your local number", "tel:",
        "learn more", "meeting options", "for organizers", "this meeting may be recorded", "join webex",
        "phone conference id", "join the meeting", "call in", "audio only", "reset pin", "local number",
    ]

    static func isBoilerplate(_ line: String) -> Bool {
        let lower = line.lowercased()
        // Dial-in numbers ("+1 213-555-0142,,123456789# United States"), or lines that are mostly digits.
        if lower.range(of: #"\+\d{1,3}[\s\-.]*\(?\d{2,4}\)?[\s\-.]*\d{3}[\s\-.]*\d{3,4}"#, options: .regularExpression) != nil {
            return true
        }
        let digits = lower.filter(\.isNumber).count
        if digits >= 7, Double(digits) / Double(max(1, lower.count)) > 0.4 { return true }
        // Boilerplate lines are short; a long line that mentions "call in" is something the organizer wrote.
        return lower.count < 80 && boilerplate.contains { lower.contains($0) }
    }

    static func withoutLinks(_ line: String) -> String {
        line.replacingOccurrences(of: #"<?https?://[^\s<>"']+>?"#, with: "", options: .regularExpression)
    }
}
