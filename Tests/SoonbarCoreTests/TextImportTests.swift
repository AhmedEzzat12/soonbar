import Foundation
import Testing
@testable import SoonbarCore

/// Dates resolve through QuickAddParser, which reads relative words against the real clock (see QuickAddParserTests).
struct TextImportTests {
    let cal = Calendar.current
    var parser: QuickAddParser { QuickAddParser(calendar: cal, now: Date()) }

    let email = """
        Let's do the design review next Tuesday at 3pm in the Studio room. Please send me the updated mockups by Monday. \
        The team dinner is on Friday Oct 30 at 7:30 pm. Day 1 (Nov 3): 09:00–10:30 Kickoff. can we meet tomorrow 11?
        """

    @Test func datesTheTextGivesAreGrounded() {
        #expect(TextImport.isGrounded("next Tuesday at 3pm", in: email))
        #expect(TextImport.isGrounded("Tuesday 3pm", in: email))
        #expect(TextImport.isGrounded("Oct 30, 7:30pm", in: email))
        #expect(TextImport.isGrounded("October 30 at 7:30 PM", in: email))
        #expect(TextImport.isGrounded("Nov 3, 9:00-10:30", in: email))
        #expect(TextImport.isGrounded("tomorrow 11:00", in: email))
    }

    @Test func calculatedOrInventedDatesAreNot() {
        #expect(!TextImport.isGrounded("Friday 11:00", in: email))
        #expect(!TextImport.isGrounded("today", in: email))
        #expect(!TextImport.isGrounded("Oct 31", in: email))
        #expect(!TextImport.isGrounded("Wednesday", in: email))
        #expect(!TextImport.isGrounded("", in: email))
    }

    @Test func wordsThatStartLikeNamesDontCount() {
        #expect(!TextImport.isGrounded("March 3", in: "Mark sent 3 files"))
        #expect(!TextImport.isGrounded("Friday", in: "a friend is coming"))
    }

    @Test func itemsTakeOnlyGroundedDates() {
        let items = TextImport.items(from: [
            TextImportCandidate(title: "Design review", kind: .event, when: "next Tuesday at 3pm", location: "Studio room"),
            TextImportCandidate(title: "Call the bank", kind: .reminder, when: "Friday 11:00"),
            TextImportCandidate(title: "Coffee", kind: .event, when: nil),
        ], sourceText: email, parser: parser)
        #expect(items.count == 3)
        #expect(items[0].hasDate)
        #expect(cal.component(.weekday, from: items[0].start) == 3)
        #expect(cal.component(.hour, from: items[0].start) == 15)
        #expect(items[0].location == "Studio room")
        #expect(!items[1].hasDate)
        #expect(items[1].kind == .reminder)
        #expect(!items[2].hasDate)
    }

    @Test func titlesStartWithACapital() {
        let items = TextImport.items(from: [TextImportCandidate(title: "design review", kind: .event, when: "tomorrow")],
                                     sourceText: "design review tomorrow", parser: parser)
        #expect(items.first?.title == "Design review")
    }

    @Test func emptyTitlesAreDropped() {
        let items = TextImport.items(from: [TextImportCandidate(title: "  ", kind: .event, when: "tomorrow")],
                                     sourceText: "tomorrow", parser: parser)
        #expect(items.isEmpty)
    }

    @Test func withoutAModelEachSentenceWithADateIsACandidate() {
        let text = "Lunch with Sara tomorrow at 1pm. The weather is nice. Remind me to pay rent on Friday!"
        let found = TextImport.candidatesWithoutModel(in: text)
        #expect(found.count == 2)
        #expect(found[0].kind == .event)
        #expect(found[0].title == "Lunch with Sara")
        #expect(found[1].kind == .reminder)
        #expect(found[1].title.hasPrefix("pay rent"))
        #expect(TextImport.items(from: found, sourceText: text, parser: parser)[1].title.hasPrefix("Pay rent"))
        let items = TextImport.items(from: found, sourceText: text, parser: parser)
        #expect(items.allSatisfy { $0.hasDate })
    }

    @Test func withoutAModelTitlesLoseFillerAndPossessiveDays() {
        let text = """
            Hi Ahmed, quick recap from today's call. Let's do the design review next Tuesday at 3pm in the Studio room.             The team dinner is on Friday Oct 30 at 7:30pm at Zooba.
            """
        let titles = TextImport.candidatesWithoutModel(in: text).map(\.title)
        #expect(titles == ["do the design review in the Studio room", "The team dinner is at Zooba"])
    }
}
