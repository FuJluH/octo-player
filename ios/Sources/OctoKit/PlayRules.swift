import Foundation

/// When a play counts, the same rule as the other apps (`shared/.../PlayRules.kt`): half the
/// song or four minutes, whichever comes first, and never for clips under 30 seconds.
public enum PlayRules {
    public static func countsAsPlay(played: TimeInterval, duration: TimeInterval) -> Bool {
        duration >= 30 && played >= min(duration / 2, 240)
    }
}
