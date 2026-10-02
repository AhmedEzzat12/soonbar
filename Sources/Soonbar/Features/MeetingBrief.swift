import SwiftUI

// Meeting brief: a small panel with attendees, notes and links shortly before a meeting.
// Off by default (PreferencesStore.meetingBriefEnabled).

/// Scheduling state for the brief; held by AppModel.
@MainActor
final class MeetingBriefState {}

extension AppModel {
    func updateMeetingBrief() {}
}

/// Alerts tab.
struct MeetingBriefSettingsSection: View {
    var body: some View { EmptyView() }
}
