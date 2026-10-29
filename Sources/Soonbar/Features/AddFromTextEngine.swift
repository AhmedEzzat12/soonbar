import Foundation
import FoundationModels
import SoonbarCore

// Add from text: finds events and reminders in pasted text. Apple Intelligence reads the text when it's available and
// the user allows it; plain date detection otherwise. Either way TextImport only keeps dates the text itself gives.
// FoundationModels exists from macOS 26; on older systems the framework is weakly linked and never touched.

enum AppleIntelligenceStatus: Equatable {
    case available
    /// A short reason to show in Settings.
    case unavailable(String)

    var isAvailable: Bool { self == .available }

    static var current: AppleIntelligenceStatus {
        guard #available(macOS 26.0, *) else { return .unavailable("Needs macOS 26 or later.") }
        return OnDeviceTextReader.status
    }
}

struct TextImportResult {
    var candidates: [TextImportCandidate]
    var usedAppleIntelligence: Bool
    /// Set when Apple Intelligence was meant to read the text but couldn't, so date detection did instead.
    var note: String?
}

enum TextImportEngine {
    /// The on-device model reads about 12,000 characters in total, including its instructions and its answer.
    static let maximumCharacters = 6_000

    static func candidates(in text: String, useAppleIntelligence: Bool, now: Date) async -> TextImportResult {
        let text = String(text.prefix(maximumCharacters))
        if useAppleIntelligence, #available(macOS 26.0, *), OnDeviceTextReader.status == .available {
            do {
                return TextImportResult(candidates: try await OnDeviceTextReader.candidates(in: text, now: now), usedAppleIntelligence: true)
            } catch {
                return TextImportResult(candidates: TextImport.candidatesWithoutModel(in: text), usedAppleIntelligence: false,
                                        note: "Apple Intelligence couldn't read this text, so dates were found without it.")
            }
        }
        return TextImportResult(candidates: TextImport.candidatesWithoutModel(in: text), usedAppleIntelligence: false)
    }
}

/// The on-device model, asked for a fixed shape of answer. The schema is built at run time rather than with the
/// @Generable macro, whose compiler plugin ships with Xcode only, so the app still builds with the Command Line Tools.
@available(macOS 26.0, *)
enum OnDeviceTextReader {
    static var status: AppleIntelligenceStatus {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale() ? .available : .unavailable("Apple Intelligence doesn't support your language yet.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac can't run Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still downloading.")
        case .unavailable:
            return .unavailable("Apple Intelligence isn't available.")
        }
    }

    static func candidates(in text: String, now: Date) async throws -> [TextImportCandidate] {
        let today = now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        let session = LanguageModelSession(instructions: """
            You find calendar events and to-do reminders in text the user pasted. Today is \(today). \
            Copy each date and time exactly as the text writes it; don't calculate or guess one. \
            Leave "when" out when the text gives no date for an item. Don't invent items the text doesn't mention.
            """)
        let response = try await session.respond(to: text, schema: schema)
        let items = try response.content.value([GeneratedContent].self, forProperty: "items")
        return items.compactMap { item in
            guard let title = try? item.value(String.self, forProperty: "title") else { return nil }
            let kind = (try? item.value(String.self, forProperty: "kind")) == "reminder" ? QuickAddKind.reminder : .event
            return TextImportCandidate(
                title: title, kind: kind,
                when: try? item.value(String?.self, forProperty: "when"),
                location: try? item.value(String?.self, forProperty: "location")
            )
        }
    }

    private static let schema: GenerationSchema = {
        let item = DynamicGenerationSchema(name: "Item", properties: [
            .init(name: "title", description: "A short title, like a calendar entry, without the date",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "kind", description: "event: happens at a set time, with other people or at a place. reminder: a task to do",
                  schema: DynamicGenerationSchema(name: "Kind", anyOf: ["event", "reminder"])),
            .init(name: "when", description: "The date and time exactly as written in the text, e.g. 'next Tuesday at 3pm'",
                  schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "location", description: "The place or meeting link, if the text gives one",
                  schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        ])
        let root = DynamicGenerationSchema(name: "Extraction", properties: [
            .init(name: "items", description: "Every event or task the text mentions, in order",
                  schema: DynamicGenerationSchema(arrayOf: item, maximumElements: 12)),
        ])
        // Only fails for a malformed schema, which this fixed one isn't.
        return try! GenerationSchema(root: root, dependencies: [])
    }()
}
