import Testing
@testable import SoonbarCore

struct NotesSummaryInputTests {
    let agenda = """
        Hi all, this is our monthly vendor sync. We'll go over the Q4 rollout timeline, the open security findings from \
        the last audit, and the new SLA proposal from the vendor. Please review the attached SLA draft before the call \
        and bring your team's capacity numbers for November, so we can agree on the rollout dates in the meeting. \
        If you can't make it, send your notes to Priya by Wednesday so they can be covered.
        """

    var teamsInvite: String {
        agenda + """

        ________________________________________________________________________________
        Microsoft Teams meeting
        Join on your computer, mobile app or room device
        Click here to join the meeting <https://teams.microsoft.com/l/meetup-join/19%3ameeting>
        Meeting ID: 123 456 789 012
        Passcode: xYz123
        Or call in (audio only)
        +1 213-555-0142,,123456789# United States, Los Angeles
        Phone Conference ID: 123 456 789#
        Find a local number | Reset PIN
        Learn More | Meeting options
        """
    }

    @Test func keepsWhatTheOrganizerWroteAndDropsTheDialIn() throws {
        let text = try #require(NotesSummaryInput.text(from: teamsInvite))
        #expect(text.contains("Q4 rollout timeline"))
        #expect(text.contains("capacity numbers"))
        for gone in ["Meeting ID", "Passcode", "213-555", "teams.microsoft.com", "Learn More", "Click here"] {
            #expect(!text.contains(gone), "still contains \(gone)")
        }
    }

    @Test func sentencesThatMentionJoiningOrCallingInStay() throws {
        let notes = agenda + "\nPlease help prepare the deck, and if you're travelling you can call in from the airport, which is fine for this one."
        let text = try #require(NotesSummaryInput.text(from: notes))
        #expect(text.contains("help prepare the deck"))
    }

    @Test func shortNotesAreReadAsTheyAre() {
        #expect(NotesSummaryInput.text(from: "Agenda: pick the launch date.") == nil)
        #expect(NotesSummaryInput.text(from: nil) == nil)
    }

    @Test func boilerplateAloneIsNotWorthSummarizing() {
        let onlyDialIn = String(repeating: "Meeting ID: 123 456 789\nPasscode: abc\n+1 213-555-0142\n", count: 20)
        #expect(NotesSummaryInput.text(from: onlyDialIn) == nil)
    }

    @Test func longNotesAreCappedToFitTheModel() throws {
        let long = String(repeating: "We will discuss the roadmap and decide on owners for each item. ", count: 200)
        let text = try #require(NotesSummaryInput.text(from: long))
        #expect(text.count == 4_000)
    }

    @Test func htmlNotesBecomePlainText() throws {
        let html = "<p>" + agenda.replacingOccurrences(of: ". ", with: ".</p><p>") + "</p><br><a href=\"https://zoom.us/j/1\">Join Zoom</a>"
        let text = try #require(NotesSummaryInput.text(from: html))
        #expect(!text.contains("<p>"))
        #expect(!text.contains("Join Zoom"))
    }
}
