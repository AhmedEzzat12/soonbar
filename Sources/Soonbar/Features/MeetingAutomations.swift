import SwiftUI

// Meeting automations: run a Shortcut when a meeting starts or ends — e.g. one that turns on a Focus.
// Off by default (PreferencesStore.meetingAutomationsEnabled).

/// Start/end tracking state; held by AppModel.
@MainActor
final class MeetingAutomationState {}

extension AppModel {
    func updateMeetingAutomations() {}
}

/// Alerts tab.
struct MeetingAutomationsSettingsSection: View {
    var body: some View { EmptyView() }
}
