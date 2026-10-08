import SoonbarCore
import SwiftUI

// Meeting brief: a small panel with attendees, notes and links shortly before a meeting.
// Off by default (PreferencesStore.meetingBriefEnabled).

/// Scheduling state for the brief; held by AppModel.
@MainActor
final class MeetingBriefState {
    let panel = MeetingBriefPanelController()
    var task: Task<Void, Never>?
    /// Occurrences already briefed, so each one appears once.
    var briefedIDs: Set<String> = []
}

extension PreferencesStore {
    var meetingBriefSettings: MeetingBriefSettings {
        MeetingBriefSettings(leadMinutes: meetingBriefLeadMinutes, onlyWithAttendees: meetingBriefOnlyWithAttendees)
    }
}

extension AppModel {
    /// Shows the brief that is due now, then sleeps until the next one, like `rescheduleMeetingAlerts()`.
    func updateMeetingBrief() {
        let state = meetingBriefState
        state.task?.cancel()
        state.briefedIDs.formIntersection(events.map(\.id))
        guard prefs.meetingBriefEnabled, eventAccess == .granted else { return }
        let settings = prefs.meetingBriefSettings
        let candidates = visibleEvents
        let due = MeetingBriefPlanner.dueBriefs(events: candidates, now: Date(), settings: settings, alreadyBriefed: state.briefedIDs)
        if let first = due.first {
            // Meetings due at the same moment are marked too; replacing the brief a minute later would be noise.
            state.briefedIDs.formUnion(due.map(\.id))
            state.panel.show(first, model: self, until: MeetingBriefPlanner.dismissDate(for: first))
        }
        guard let next = MeetingBriefPlanner.nextBriefDate(
            events: candidates, now: Date(), settings: settings, alreadyBriefed: state.briefedIDs
        ) else { return }
        state.task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 0.05))
            guard !Task.isCancelled else { return }
            self?.updateMeetingBrief()
        }
    }

    /// Shows the brief for the next meeting (or a sample) until it is closed, so the look can be checked from Settings.
    func previewMeetingBrief() {
        let now = Date()
        let upcoming = MeetingBriefPlanner.nextMeeting(events: visibleEvents, now: now, settings: prefs.meetingBriefSettings)
        meetingBriefState.panel.show(upcoming ?? sampleBriefEvent(now: now), model: self, until: nil)
    }

    private func sampleBriefEvent(now: Date) -> CalendarEvent {
        let start = now.addingTimeInterval(TimeInterval(prefs.meetingBriefLeadMinutes * 60))
        return CalendarEvent(
            id: "preview", title: "Launch planning", start: start, end: start.addingTimeInterval(30 * 60),
            calendarID: writableCalendars(for: .event).first?.id ?? "preview",
            location: "Studio, 2nd floor",
            url: URL(string: "https://meet.google.com/abc-defg-hij"),
            notes: "Goals:\n- Pick the launch date\n- Review the onboarding flow\nDeck: https://docs.northwind.io/launch-deck",
            attendees: [
                Attendee(name: "Jane Doe", email: "jane@bluebird.com", status: .accepted, isOrganizer: true),
                Attendee(name: "Sam Lee", email: "sam@northwind.io", status: .tentative),
                Attendee(email: "alex@northwind.io", status: .pending),
                Attendee(name: "Priya Shah", email: "priya@bluebird.com", status: .declined),
                Attendee(name: "You", status: .accepted, isCurrentUser: true),
            ]
        )
    }
}

/// Alerts tab.
struct MeetingBriefSettingsSection: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Show a meeting brief before meetings", isOn: $prefs.meetingBriefEnabled)
            Picker("Show it", selection: $prefs.meetingBriefLeadMinutes) {
                ForEach([2, 5, 10], id: \.self) { Text("\($0) minutes before").tag($0) }
            }
            .disabled(!prefs.meetingBriefEnabled)
            Toggle("Only for meetings with other people", isOn: $prefs.meetingBriefOnlyWithAttendees)
                .disabled(!prefs.meetingBriefEnabled)
            TrailingButtons {
                Button("Preview Brief") { model.previewMeetingBrief() }
            }
        } header: {
            Text("Meeting brief")
        } footer: {
            SectionFooter("A small panel in the top-right corner shows who's coming, the notes and any links. "
                          + "It never takes focus and closes a couple of minutes after the meeting starts.")
        }
        .onChange(of: prefs.meetingBriefEnabled) { _, enabled in
            // Turning the brief off also closes one that's showing.
            if !enabled { model.meetingBriefState.panel.dismiss() }
            model.updateMeetingFeatures()
        }
        .onChange(of: prefs.meetingBriefSettings) { model.updateMeetingFeatures() }
    }
}
