import Foundation
import FoundationModels
import SoonbarCore

// Summaries of long invitation notes for the meeting brief, written by Apple Intelligence on this Mac.
// Off by default (PreferencesStore.meetingBriefSummaries); without Apple Intelligence the brief shows the notes as before.

@MainActor
enum NotesSummarizer {
    /// Results per event and notes, so reopening a brief or previewing again doesn't ask the model twice.
    private static var cache: [String: NotesSummary] = [:]

    /// The cleaned notes to summarize, when the feature can run for this event.
    static func input(for event: CalendarEvent, prefs: PreferencesStore) -> String? {
        guard prefs.meetingBriefSummaries, AppleIntelligenceStatus.current.isAvailable else { return nil }
        return NotesSummaryInput.text(from: event.notes)
    }

    static func cached(for event: CalendarEvent, input: String) -> NotesSummary? {
        cache[key(event, input)]
    }

    /// nil when Apple Intelligence couldn't summarize; the brief then keeps showing the notes.
    static func summary(for event: CalendarEvent, input: String) async -> NotesSummary? {
        if let cached = cached(for: event, input: input) { return cached }
        guard #available(macOS 26.0, *), let summary = try? await OnDeviceNotesSummarizer.summarize(input, title: event.title) else {
            return nil
        }
        cache[key(event, input)] = summary
        return summary
    }

    private static func key(_ event: CalendarEvent, _ input: String) -> String { "\(event.id)|\(input.hashValue)" }
}

/// The schema is built at run time rather than with @Generable, so the app still builds with the Command Line Tools.
@available(macOS 26.0, *)
private enum OnDeviceNotesSummarizer {
    static func summarize(_ notes: String, title: String) async throws -> NotesSummary? {
        let session = LanguageModelSession(instructions: """
            You summarize a meeting invitation for someone about to attend it. Use only what the text says; \
            don't add advice or details it doesn't contain. Keep points short, but never drop words that change \
            their meaning (who, when, which).
            """)
        let response = try await session.respond(to: "Meeting: \(title)\n\n\(notes)", schema: schema)
        let content = response.content
        let gist = try content.value(String.self, forProperty: "gist").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gist.isEmpty else { return nil }
        let agenda = (try? content.value([String].self, forProperty: "agenda")) ?? []
        let asks = (try? content.value([String].self, forProperty: "asks")) ?? []
        return NotesSummary(gist: gist, agenda: agenda.filter { !$0.isEmpty }, asks: asks.filter { !$0.isEmpty })
    }

    private static let schema: GenerationSchema = {
        let root = DynamicGenerationSchema(name: "Summary", properties: [
            .init(name: "gist", description: "What the meeting is for, in one short sentence",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "agenda", description: "The main topics, each a short phrase that keeps its full meaning",
                  schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self), maximumElements: 5)),
            .init(name: "asks", description: "What the reader is asked to prepare or do before or in the meeting; empty if nothing",
                  schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self), maximumElements: 4)),
        ])
        // Only fails for a malformed schema, which this fixed one isn't.
        return try! GenerationSchema(root: root, dependencies: [])
    }()
}
