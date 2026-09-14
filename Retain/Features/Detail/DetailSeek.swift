import Foundation

/// Where a click lands in the audio.
///
/// Four things in the detail window are jump targets — a transcript line, a
/// chapter row, a marker, and a source chip under a chat answer — and the
/// arithmetic behind all four is the same: resolve the thing to a second, then
/// keep that second inside the recording. Pulling it out of the views is what
/// lets it be tested without an audio device.
nonisolated enum DetailSeek {

    /// A line seeks to where the line starts, never to the middle of it. A
    /// second of lead-in is what makes the first word audible rather than
    /// clipped, but it is not drawn anywhere, so there is none: the board says
    /// the timestamp beside the line is the line's position, and seeking
    /// somewhere else would make the number a lie.
    static func target(forLineStartingAt start: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        clamped(start, duration: duration)
    }

    /// A chapter row, and the marker dot on it, both seek to the minute the
    /// block started — which is the number the row draws.
    static func target(forChapterAt time: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        clamped(time, duration: duration)
    }

    /// A source chip under a chat answer.
    ///
    /// A transcript chip carries its own second. A note chip carries a block
    /// number, and the second is the block's start — the same target the
    /// chapter row for that block uses, so citing "Note 3" and clicking
    /// chapter 3 land in the same place.
    ///
    /// `nil` for a note that no longer exists. `ChatAnswering.turn(from:…)`
    /// already drops those, and this is the second place that has to agree,
    /// because the notes can be written again after the answer was.
    static func target(
        for reference: ChatReference,
        blocks: [NoteBlock],
        duration: TimeInterval?
    ) -> TimeInterval? {
        switch reference {
        case let .transcript(time):
            return clamped(time, duration: duration)
        case let .note(number):
            guard let block = blocks.first(where: { $0.number == number }) else { return nil }
            return clamped(block.start, duration: duration)
        }
    }

    /// Never before the first second, never past the last one.
    ///
    /// A duration of zero is a recording that is still running or whose length
    /// was never written down; it is treated as unknown rather than as a
    /// recording nothing can be sought inside.
    static func clamped(_ time: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        let floored = max(0, time)
        guard let duration, duration > 0 else { return floored }
        return min(floored, duration)
    }
}
