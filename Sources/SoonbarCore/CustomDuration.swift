import Foundation

/// The units a custom duration can be typed in (Settings).
public enum DurationUnit: String, CaseIterable, Sendable {
    case seconds, minutes

    public var seconds: Int { self == .seconds ? 1 : 60 }
}

/// Custom durations typed in Settings: shown in the unit they read best in, kept within a sensible range.
public enum CustomDuration {
    /// Whole minutes read as minutes ("2 minutes", not "120 seconds"); anything else as seconds. `allowed` limits the
    /// units on offer, e.g. lead times that only make sense in minutes.
    public static func split(_ seconds: Int, allowed: [DurationUnit] = DurationUnit.allCases) -> (value: Int, unit: DurationUnit) {
        if allowed.contains(.minutes), seconds % 60 == 0 || !allowed.contains(.seconds) { return (seconds / 60, .minutes) }
        return (seconds, .seconds)
    }

    public static func seconds(_ value: Int, _ unit: DurationUnit, within range: ClosedRange<Int>) -> Int {
        min(max(value * unit.seconds, range.lowerBound), range.upperBound)
    }

    /// "45 seconds", "1 minute", "90 seconds", "3 minutes".
    public static func label(_ seconds: Int) -> String {
        let (value, unit) = split(seconds)
        return value == 1 ? "1 \(unit == .seconds ? "second" : "minute")" : "\(value) \(unit.rawValue)"
    }
}
