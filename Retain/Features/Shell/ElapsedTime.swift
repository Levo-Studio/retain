import Foundation

/// How long something has been running, in the two shapes the design draws it.
///
/// Pure and free of any locale, which is deliberate for `clock`: `00:47:12` is
/// a duration into a recording, not a time of day, and it reads the same in
/// every language. Everything that *is* prose — "Recording for 47 minutes" —
/// is a string catalog key at the call site and takes the number from here.
nonisolated enum ElapsedTime {

    /// `hh:mm:ss`, zero padded, which is what the title-bar pill and the
    /// popover's large timer show.
    ///
    /// The hours are not dropped below an hour. A timer that changes width when
    /// it passes 01:00:00 makes everything beside it move, and the design draws
    /// the pill and the header row as fixed things.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
    }

    /// `mm:ss` — a timestamp on a transcript line, where the recording is the
    /// timeline and an hour in is still `47:12`.
    ///
    /// The export draws transcript timestamps as `00:46:03`, so this is only
    /// here for the places that need the short form; the rails use `clock`.
    static func shortClock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds.rounded(.down)))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }

    /// Whole minutes, rounded down — "Recording for 47 minutes" is 47 after
    /// forty-seven minutes and not after forty-six and a half.
    static func wholeMinutes(_ seconds: TimeInterval) -> Int {
        Int(max(0, seconds) / 60)
    }
}
