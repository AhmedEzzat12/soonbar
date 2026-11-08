import Foundation
import MetricKit
import TelemetryDeck

/// Anonymous usage statistics through TelemetryDeck: how many Macs run Soonbar and which versions, which optional
/// features are on, and a short summary when it crashes. Never calendar data, names, or anything typed; each Mac is
/// counted under a random anonymous ID. On unless turned off (Settings → General → Privacy), and silent until the
/// maintainer puts an App ID in Info.plist (`TelemetryDeckAppID`).
@MainActor
final class UsageStatistics: NSObject, MXMetricManagerSubscriber {
    static let shared = UsageStatistics()
    private var isRunning = false
    private weak var prefs: PreferencesStore?
    private static let lastSnapshotKey = "usageStatisticsLastSnapshotDay"

    private static var appID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String,
              !id.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return id
    }

    /// Starts or stops sending to match the setting; called at launch and when the setting changes.
    func apply(_ prefs: PreferencesStore) {
        self.prefs = prefs
        if prefs.shareUsageStatistics { start() } else { stop() }
    }

    private func start() {
        guard !isRunning, let appID = Self.appID else { return }
        isRunning = true
        let config = TelemetryDeck.Config(appID: appID)
        // Copies that can't update themselves come from source or development builds; keep them out of the real numbers.
        config.testMode = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") == nil
        TelemetryDeck.initialize(config: config)
        MXMetricManager.shared.add(self)
        sendDailySnapshot()
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        MXMetricManager.shared.remove(self)
        TelemetryDeck.terminate()
    }

    /// Which optional features are on, at most once a day: yes/no only, never what's in them.
    func sendDailySnapshot() {
        guard isRunning, let prefs else { return }
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: Self.lastSnapshotKey) != today else { return }
        defaults.set(today, forKey: Self.lastSnapshotKey)
        let features: [String: Bool] = [
            "meetingAlerts": prefs.meetingAlertsEnabled,
            "meetingBrief": prefs.meetingBriefEnabled,
            "notesSummaries": prefs.meetingBriefSummaries,
            "addFromText": prefs.addFromTextEnabled,
            "freeTimes": prefs.shareAvailabilityEnabled,
            "secondTimeZone": prefs.secondTimeZoneID != nil,
            "backToBackMarks": prefs.markBackToBack,
            "keepCurrentMeeting": prefs.showMeetingTimeLeft,
            "invitations": prefs.markUnansweredInvites,
            "meetingShortcuts": prefs.meetingAutomationsEnabled,
        ]
        TelemetryDeck.signal("Settings.daily", parameters: features.mapValues { $0 ? "on" : "off" })
    }

    // MARK: - Crashes

    /// macOS hands over its own crash reports on a later launch; only the kind of crash and the version are sent.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.flatMap { $0.crashDiagnostics ?? [] }.map { crash in
            [
                "version": crash.applicationVersion,
                "build": crash.metaData.applicationBuildVersion,
                "exceptionType": crash.exceptionType.map { "\($0)" } ?? "none",
                "signal": crash.signal.map { "\($0)" } ?? "none",
                "terminationReason": String((crash.terminationReason ?? "none").prefix(120)),
            ]
        }
        guard !crashes.isEmpty else { return }
        Task { @MainActor in
            guard self.isRunning else { return }
            for crash in crashes { TelemetryDeck.signal("App.crashed", parameters: crash) }
        }
    }
}
