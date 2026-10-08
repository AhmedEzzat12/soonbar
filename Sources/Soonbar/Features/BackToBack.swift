import SoonbarCore
import SwiftUI

// Back-to-back meetings: time left in the current meeting in the menu bar, and agenda marks for
// meetings with no break before them. Off by default (showMeetingTimeLeft, markBackToBack).

/// Menu Bar tab.
struct MeetingTimeLeftSettingsSection: View {
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Show time left during a meeting", isOn: $prefs.showMeetingTimeLeft)
                .disabled(!prefs.showNextEvent)
        } header: {
            Text("During a meeting")
        } footer: {
            SectionFooter("For example “Standup · 12m left”, or “Standup · 3m left → Design review” when the next "
                          + "meeting starts right after. The last 5 minutes are shown in red.")
        }
    }
}

extension AppModel {
    /// Event id → the meeting it follows with no break; empty while the setting is off.
    var backToBackPredecessors: [String: BackToBackLink] {
        guard prefs.markBackToBack else { return [:] }
        return BackToBackDetector.predecessors(events: visibleEvents, gapMinutes: prefs.backToBackGapMinutes, calendar: calendar)
    }
}

extension BackToBackLink {
    /// Tooltip and accessibility label for the agenda mark.
    var label: String { overlaps ? "Overlaps \(previousTitle)" : "Starts right after \(previousTitle)" }
}

/// Calendar tab.
struct BackToBackSettingsSection: View {
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Mark meetings with no break before them", isOn: $prefs.markBackToBack)
            Picker("Counts as back-to-back", selection: $prefs.backToBackGapMinutes) {
                Text("No gap").tag(0)
                Text("5 minutes or less").tag(5)
                Text("10 minutes or less").tag(10)
            }
            .disabled(!prefs.markBackToBack)
        } header: {
            Text("Back-to-back meetings")
        } footer: {
            SectionFooter("The agenda marks a meeting with an orange arrow when it starts right after another one or overlaps it.")
        }
    }
}
