import AppKit
import SoonbarCore
import SwiftUI

// Share availability: copy upcoming free times as text, ready to paste into a chat or email.
// Off by default (PreferencesStore.shareAvailabilityEnabled).

extension AppModel {
    var availabilitySettings: AvailabilitySettings {
        AvailabilitySettings(
            workingDays: prefs.availabilityDays, workingHours: prefs.workingHours, minimumMinutes: prefs.availabilityMinMinutes
        )
    }

    /// The text "Free times" copies; nil when nothing is free. Fetches its own range because the
    /// availability window can reach past the events the popover has loaded.
    func availabilityText(now: Date) -> String? {
        let calendar = calendar
        let settings = availabilitySettings
        guard eventAccess == .granted,
              let interval = AvailabilityPlanner.interval(now: now, settings: settings, calendar: calendar) else { return nil }
        // Duplicates don't change free time, so only hidden calendars, declined and cancelled events are dropped.
        let events = EventPipeline.visible(
            service.events(in: interval), hiddenCalendarIDs: prefs.hiddenCalendarIDs, hideDuplicates: false, calendarPriority: []
        )
        let days = AvailabilityPlanner.days(events: events, now: now, settings: settings, calendar: calendar)
        return AvailabilityFormatter.text(
            days, includeTimeZone: prefs.availabilityIncludeTimeZone, calendar: calendar, locale: .current
        )
    }

    func copyAvailability() {
        guard let text = availabilityText(now: Date()) else {
            showToast("No free time in the next \(prefs.availabilityDays) working days")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("Free times copied")
    }
}

/// Calendar tab.
struct ShareAvailabilitySettingsSection: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(AppModel.self) private var model
    @State private var preview: String?

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Copy free times from the popover", isOn: $prefs.shareAvailabilityEnabled)
            Group {
                Picker("Days to include", selection: $prefs.availabilityDays) {
                    ForEach([3, 5, 10], id: \.self) { Text("\($0) working days").tag($0) }
                }
                Picker("Shortest slot", selection: $prefs.availabilityMinMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
                Toggle("Include time zone", isOn: $prefs.availabilityIncludeTimeZone)
                LabeledContent("Preview") {
                    Text(previewText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // On the row itself: modifiers on a Form Section or Group can repeat for every row.
                .task(id: PreviewInputs(model: model, prefs: prefs)) {
                    preview = model.availabilityText(now: model.now)
                }
            }
            .disabled(!prefs.shareAvailabilityEnabled)
        } header: {
            Text("Share availability")
        } footer: {
            SectionFooter(
                "Weekdays only, within your working hours (\(GeneralSettingsView.label(prefs.workingHoursStart))–"
                    + "\(GeneralSettingsView.label(prefs.workingHoursEnd))), set under Free time in the General tab. "
                    + "All-day events and hidden calendars don't count as busy."
            )
        }
    }

    private var previewText: String {
        if model.eventAccess != .granted { return "Calendar access is off." }
        return preview ?? "Nothing free in the next \(prefs.availabilityDays) working days."
    }

    /// Everything the preview depends on, so it recomputes when any of it changes.
    private struct PreviewInputs: Equatable {
        let settings: AvailabilitySettings
        let includeTimeZone: Bool
        let access: AccessState
        let hidden: Set<String>
        let now: Date
        let events: [CalendarEvent]

        @MainActor init(model: AppModel, prefs: PreferencesStore) {
            settings = model.availabilitySettings
            includeTimeZone = prefs.availabilityIncludeTimeZone
            access = model.eventAccess
            hidden = prefs.hiddenCalendarIDs
            now = model.now
            events = model.events
        }
    }
}
