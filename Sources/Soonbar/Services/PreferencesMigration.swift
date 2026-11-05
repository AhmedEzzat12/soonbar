import Foundation

/// Soonbar's identifier changed (to com.zod.soonbar, ahead of the App Store), and macOS keeps settings per identifier.
/// On the first launch under the new one, settings saved under the old identifier are copied over once.
/// Sandboxed builds can't read another app's settings, so there this does nothing.
enum PreferencesMigration {
    static let previousIdentifier = "com.ahmede.Soonbar"
    private static let doneKey = "migratedPreferencesFromPreviousIdentifier"

    /// Must run before anything reads or writes settings (Sparkle included).
    static func run(defaults: UserDefaults = .standard) {
        guard let identifier = Bundle.main.bundleIdentifier, identifier != previousIdentifier,
              !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard let old = defaults.persistentDomain(forName: previousIdentifier), !old.isEmpty else { return }
        // Only fill in what isn't set yet, so nothing chosen under the new identifier is overwritten.
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
