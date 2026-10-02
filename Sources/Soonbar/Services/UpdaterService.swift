import AppKit
import Observation
import Sparkle

/// Sparkle auto-updates from the appcast published with each GitHub Release.
/// Only builds that carry an update-signing public key (release builds from CI) turn it on:
/// a build without one couldn't verify an update, so it never checks.
@MainActor
@Observable
final class UpdaterService: NSObject, SPUStandardUserDriverDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        if !publicKey.isEmpty {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        }
        // On unless the user turned it off (SUEnableAutomaticChecks in Info.plist sets the default).
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    var isEnabled: Bool { controller != nil }

    /// Stored so Settings observes it; Sparkle keeps the user's choice in its own defaults.
    var automaticallyChecks = false {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // Menu bar apps have no Dock icon to badge; let Sparkle present scheduled updates gently.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
