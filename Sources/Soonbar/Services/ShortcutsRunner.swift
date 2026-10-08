import AppKit

/// Runs and lists the user's Shortcuts through the `shortcuts` command-line tool. Apps can't switch a Focus
/// themselves, but a Shortcut with "Set Focus" can.
enum ShortcutsRunner {
    private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")
    /// Runs one at a time, in order, so a meeting's end Shortcut never overtakes the next one's start.
    private static let runQueue = DispatchQueue(label: "Soonbar.ShortcutsRunner.run")
    /// A Shortcut waiting for input would otherwise hold up every later run.
    private static let timeout: TimeInterval = 60

    /// True when the Shortcut finished successfully.
    static func run(_ name: String) async -> Bool {
        await withCheckedContinuation { continuation in
            runQueue.async {
                continuation.resume(returning: execute(["run", name])?.status == 0)
            }
        }
    }

    /// Shortcut names sorted for a picker; empty if the tool fails.
    static func list() async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let result = execute(["list"], captureOutput: true), result.status == 0 else { return continuation.resume(returning: []) }
                let names = Set(String(decoding: result.output, as: UTF8.self)
                    .split(whereSeparator: \.isNewline)
                    .map { String($0) }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                continuation.resume(returning: names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
            }
        }
    }

    static func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Blocks the calling (background) thread; nil if the tool couldn't start or timed out.
    private static func execute(_ arguments: [String], captureOutput: Bool = false) -> (status: Int32, output: Data)? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = captureOutput ? pipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        // Drain on another thread so a long list can't fill the pipe and stall the tool before it exits.
        var output = Data()
        let drained = DispatchGroup()
        if captureOutput {
            drained.enter()
            DispatchQueue.global(qos: .utility).async {
                output = pipe.fileHandleForReading.readDataToEndOfFile()
                drained.leave()
            }
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        drained.wait()
        return (process.terminationStatus, output)
    }
}
