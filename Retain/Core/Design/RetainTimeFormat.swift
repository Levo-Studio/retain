import Foundation

/// The clock forms the export draws, and the pieces a duration is written out
/// of.
///
/// A position in a recording appears in three shapes across boards 03 and 04,
/// and they are not interchangeable:
///
/// - `00:52:10` — a transcript line, the "You · …" label on an annotation, and
///   a chat source chip. **Hours are always written**, including the zero hour:
///   the board draws `00:50:14` forty-nine minutes into the lecture.
/// - `00:04`, `01:14` — the chapter rail, which is hours and minutes. Over a
///   ninety-two minute recording the board's last chapter reads `01:14`, so
///   these are not minutes and seconds.
/// - `92 min`, `13 h 24 min` — durations. The *numbers* are here; the words
///   around them are copy, so each screen composes its own from the string
///   catalog rather than this file carrying a localised format.
///
/// It sits in the design layer because which of the three a place uses is
/// something the export decides, not something a screen is free to pick.
nonisolated enum RetainTimeFormat {

    /// `HH:MM:SS`, hours always present.
    static func clock(_ seconds: TimeInterval) -> String {
        let parts = components(seconds)
        return String(format: "%02d:%02d:%02d", parts.hours, parts.minutes, parts.seconds)
    }

    /// `HH:MM` — the chapter rail's form.
    static func hourMinute(_ seconds: TimeInterval) -> String {
        let parts = components(seconds)
        return String(format: "%02d:%02d", parts.hours, parts.minutes)
    }

    /// A duration in whole minutes, rounded to nearest rather than down: a
    /// lecture of 91 minutes and 40 seconds is drawn as 92 min, which is what
    /// the person who sat through it would say.
    static func wholeMinutes(_ seconds: TimeInterval) -> Int {
        Int((max(0, seconds) / 60).rounded())
    }

    /// A total split for "13 h 24 min". Minutes are the remainder, so the two
    /// numbers together never read as more time than there was.
    static func hoursAndMinutes(_ seconds: TimeInterval) -> (hours: Int, minutes: Int) {
        let minutes = wholeMinutes(seconds)
        return (minutes / 60, minutes % 60)
    }

    /// Whether a duration is long enough to be worth writing in hours.
    static func spansAnHour(_ seconds: TimeInterval) -> Bool {
        wholeMinutes(seconds) >= 60
    }

    // MARK: -

    /// Truncating, not rounding: a line that starts at 50.9 seconds is at
    /// 00:00:50, because seeking to it has to land before the first word and
    /// not after it.
    private static func components(_ seconds: TimeInterval) -> (hours: Int, minutes: Int, seconds: Int) {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        return (total / 3600, (total % 3600) / 60, total % 60)
    }
}
