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

/// Calendar tab.
struct BackToBackSettingsSection: View {
    var body: some View { EmptyView() }
}
