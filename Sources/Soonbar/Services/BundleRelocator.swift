import AppKit

/// Keeps the app installed as `<CFBundleName>.app`. Sparkle replaces an app in place, under whatever
/// file name the installed copy had, so an update that arrives through a differently named install
/// leaves the new app under the old name. On launch we rename ourselves and relaunch from the new path.
enum BundleRelocator {
    /// Returns true when a relaunch is underway and the caller should stop launching.
    static func relocateIfNeeded() -> Bool {
        let fileManager = FileManager.default
        let current = Bundle.main.bundleURL.standardizedFileURL
        guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
              current.pathExtension == "app",
              current.lastPathComponent != "\(name).app",
              // Gatekeeper's read-only translocation mount; renaming there is pointless.
              !current.path.contains("/AppTranslocation/"),
              fileManager.isWritableFile(atPath: current.deletingLastPathComponent().path)
        else { return false }

        let target = current.deletingLastPathComponent().appendingPathComponent("\(name).app")
        do {
            if fileManager.fileExists(atPath: target.path) {
                // Both copies exist: keep the newer one under the proper name, the other goes to the Trash.
                if buildNumber(of: target) > buildNumber(of: current) {
                    try fileManager.trashItem(at: current, resultingItemURL: nil)
                    relaunch(at: target)
                    return true
                }
                try fileManager.trashItem(at: target, resultingItemURL: nil)
            }
            try fileManager.moveItem(at: current, to: target)
        } catch {
            NSLog("Soonbar: could not rename %@ to %@: %@", current.path, target.lastPathComponent, error.localizedDescription)
            return false
        }
        relaunch(at: target)
        return true
    }

    private static func buildNumber(of bundleURL: URL) -> Int {
        let version = Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return version.flatMap(Int.init) ?? 0
    }

    /// Opens the app at `url` once this process has exited; while we're alive, LaunchServices would
    /// just hand the launch to us (same bundle identifier).
    private static func relaunch(at url: URL) {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$2\"",
                            "sh", String(ProcessInfo.processInfo.processIdentifier), url.path]
        try? helper.run()
        NSApp.terminate(nil)
    }
}
