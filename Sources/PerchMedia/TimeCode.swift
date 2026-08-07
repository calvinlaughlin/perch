import Foundation

/// Playback positions as a player writes them: `3:07`, `1:02:44`.
///
/// Not a `DateComponentsFormatter`. That one localises, abbreviates, and drops leading units in
/// ways that make the two ends of a scrubber disagree about their own width — the elapsed side
/// changing from `9:59` to `10:00` is fine, changing from `59` to `1:00` is a layout jump. This
/// always spells minutes, and only spells hours when there are any.
public enum TimeCode {

    /// Format seconds as `m:ss`, or `h:mm:ss` past an hour.
    ///
    /// Negative and non-finite inputs come back as `--:--` rather than as a guess: a player that
    /// reports nonsense should look like it reported nothing.
    public static func text(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return placeholder }

        // Rounded down, not to nearest: a track shows 0:00 for its first second the way every
        // other player does, and the last second is not spent displaying the whole duration.
        let total = Int(seconds.rounded(.down))
        let (hours, minutes, remainder) = (total / 3600, (total % 3600) / 60, total % 60)

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    /// What to show when there is no position to show.
    public static let placeholder = "--:--"
}
