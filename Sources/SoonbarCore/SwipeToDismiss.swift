import Foundation

/// Swiping a card away to the right, like a notification: how far it follows the pointer, how it fades, and
/// whether letting go dismisses it or springs it back.
public enum SwipeToDismiss {
    /// Past this share of the card's width, letting go dismisses it.
    static let distanceShare = 0.35
    /// A flick faster than this (points per second, to the right) dismisses it from a shorter distance.
    static let flickSpeed = 600.0
    /// …but only once it has moved this far, so a twitch while clicking doesn't throw it away.
    static let flickMinimumOffset = 16.0

    /// `offset` is how far right the pointer has moved since the swipe began; negative is to the left.
    public static func shouldDismiss(offset: Double, velocity: Double, width: Double) -> Bool {
        offset >= width * distanceShare || (offset >= flickMinimumOffset && velocity >= flickSpeed)
    }

    /// The card follows to the right only; moving left keeps it in its place.
    public static func position(for offset: Double) -> Double { max(0, offset) }

    /// Fully opaque at rest, fading to 0.3 once it has moved a full card's width.
    public static func opacity(offset: Double, width: Double) -> Double {
        guard width > 0 else { return 1 }
        return 1 - 0.7 * min(1, position(for: offset) / width)
    }
}
