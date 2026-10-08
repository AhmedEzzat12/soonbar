import SoonbarCore
import SwiftUI

// Meeting automations: run a Shortcut when a meeting starts or ends — e.g. one that turns on a Focus.
// Off by default (PreferencesStore.meetingAutomationsEnabled).

/// Start/end tracking state; held by AppModel.
@MainActor
final class MeetingAutomationState {
    /// nil until the first check after launch or after the feature is turned on.
    var tracker: MeetingAutomationTracker.State?
}

extension AppModel {
    func updateMeetingAutomations() {
        let settings = MeetingAutomationSettings(
            isEnabled: prefs.meetingAutomationsEnabled && eventAccess == .granted,
            onlyWithVideoLink: prefs.meetingAutomationsVideoOnly
        )
        let result = MeetingAutomationTracker.evaluate(
            previous: meetingAutomationState.tracker, events: visibleEvents, now: Date(), settings: settings
        )
        meetingAutomationState.tracker = result.state
        let names = result.actions.compactMap { $0 == .start ? prefs.meetingStartShortcut : prefs.meetingEndShortcut }
        guard !names.isEmpty else { return }
        // One task, so an end Shortcut always finishes before the next block's start runs.
        Task { [weak self] in
            for name in names where await !ShortcutsRunner.run(name) {
                self?.showToast("Couldn't run \(name)")
            }
        }
    }
}

/// Alerts tab.
struct MeetingAutomationsSettingsSection: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(AppModel.self) private var model
    /// nil until the list has loaded once.
    @State private var shortcuts: [String]?
    @State private var isLoading = false
    @State private var testing: String?
    @State private var testResult: String?

    var body: some View {
        @Bindable var prefs = prefs
        let enabled = prefs.meetingAutomationsEnabled
        Section {
            Toggle("Run Shortcuts when meetings start and end", isOn: $prefs.meetingAutomationsEnabled)
            shortcutPicker("When a meeting starts", selection: $prefs.meetingStartShortcut)
            shortcutPicker("When it ends", selection: $prefs.meetingEndShortcut)
            if let testResult {
                Text(testResult).font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Only for events with a video call link", isOn: $prefs.meetingAutomationsVideoOnly)
                .disabled(!enabled)
            TrailingButtons {
                Button("Refresh List") { Task { await loadShortcuts() } }
                    .disabled(!enabled || isLoading)
                Button("Open Shortcuts") { ShortcutsRunner.openApp() }
            }
        } header: {
            Text("Meeting automations")
        } footer: {
            SectionFooter(
                "A Shortcut with the “Set Focus” action can turn on Do Not Disturb when a meeting starts, and another can "
                    + "turn it off when it ends. Back-to-back meetings count as one."
            )
        }
        .task(id: enabled) {
            if enabled, shortcuts == nil { await loadShortcuts() }
        }
        .onChange(of: prefs.meetingAutomationsEnabled) { model.updateMeetingFeatures() }
        .onChange(of: prefs.meetingAutomationsVideoOnly) { model.updateMeetingFeatures() }
    }

    private func shortcutPicker(_ title: String, selection: Binding<String?>) -> some View {
        let available = shortcuts ?? []
        return LabeledContent(title) {
            HStack {
                Picker(title, selection: selection) {
                    Text("None").tag(String?.none)
                    // Keep a renamed or deleted Shortcut visible so the setting doesn't silently change.
                    if let current = selection.wrappedValue, !available.contains(current) {
                        Text(shortcuts == nil ? current : "\(current) (missing)").tag(String?.some(current))
                    }
                    if !available.isEmpty { Divider() }
                    ForEach(available, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden()
                Button("Test") {
                    if let name = selection.wrappedValue { Task { await test(name) } }
                }
                .disabled(selection.wrappedValue == nil || testing != nil)
            }
        }
        .disabled(!prefs.meetingAutomationsEnabled)
    }

    private func loadShortcuts() async {
        isLoading = true
        shortcuts = await ShortcutsRunner.list()
        isLoading = false
    }

    /// Reports inline: the popover's toast isn't visible while Settings is in front.
    private func test(_ name: String) async {
        testing = name
        testResult = "Running “\(name)”…"
        testResult = await ShortcutsRunner.run(name) ? "Ran “\(name)”." : "Couldn't run “\(name)”."
        testing = nil
    }
}
