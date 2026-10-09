import SoonbarCore
import SwiftUI

// Invitations: dim meetings you haven't firmly accepted, and count the ones waiting for a reply.
// Off by default (PreferencesStore.markUnansweredInvites). Replying needs Calendar: EventKit can't answer invites.

extension AppModel {
    /// Upcoming invitations without a reply; empty while the feature is off.
    var invitationsAwaitingReply: [CalendarEvent] {
        guard prefs.markUnansweredInvites else { return [] }
        return InviteStatus.awaitingReply(events: visibleEvents, now: now)
    }
}

/// A line at the top of the agenda; clicking opens Calendar, where invitations are answered.
struct InvitationsBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let waiting = model.invitationsAwaitingReply
        if let first = waiting.first {
            Button {
                CalendarAppLauncher.open(eventIdentifier: first.eventIdentifier)
            } label: {
                Label(waiting.count == 1 ? "1 invitation waiting for your reply" : "\(waiting.count) invitations waiting for your reply",
                      systemImage: "envelope.badge")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .help("Answer in Calendar")
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }
}

/// Calendar tab.
struct InvitationsSettingsSection: View {
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Mark invitations I haven't accepted", isOn: $prefs.markUnansweredInvites)
        } header: {
            Text("Invitations")
        } footer: {
            SectionFooter("Unanswered and “maybe” meetings are dimmed with a note, and the agenda counts invitations "
                          + "waiting for a reply. Clicking the count opens Calendar, where you can answer them.")
        }
    }
}
