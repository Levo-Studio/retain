import Foundation

/// Where a click in the detail window takes the reader.
///
/// Three things on boards 03 and 04 point somewhere — a chapter row, a source
/// chip under a chat answer, and a search hit arriving from the library — and
/// none of them can move a playhead: the audio is deleted as soon as its
/// transcript is written, so a recording with no file is the ordinary case and
/// not a failure. What is left is the text, and each of the three resolves to a
/// place in it: a line of the transcript, or a note block.
///
/// The timestamps stay drawn everywhere. They are still where in the lecture
/// something was said. They just no longer address a file.
///
/// The arithmetic is here rather than in the views so that it can be tested
/// without a window.
nonisolated enum DetailReveal {

    /// A place in the detail window.
    enum Target: Hashable, Sendable {
        /// One line of the transcript, which is the transcript tab.
        case line(TranscriptLine.ID)

        /// One note block, by the number the chapter rail and a chat citation
        /// both count in, which is the notes tab.
        case block(Int)
    }

    /// One ask to bring a target into view.
    ///
    /// The ordinal is what makes clicking the same chapter twice two asks
    /// rather than one. A pane watches this value, and a second request equal
    /// to the first would not be a change at all — which is a control that
    /// works once and then looks broken, the exact thing this change exists to
    /// avoid.
    struct Request: Hashable, Sendable {
        let target: Target
        let ordinal: Int
    }

    // MARK: - Resolving a second

    /// The line a second falls in.
    ///
    /// A second in a gap — a pause, or a stretch nobody spoke in — resolves to
    /// the line before it rather than the one after. That is the sentence that
    /// was being said, and something pointing into a gap came from the passage
    /// that ended there.
    static func line(at time: TimeInterval, in lines: [TranscriptLine]) -> TranscriptLine.ID? {
        guard !lines.isEmpty else { return nil }

        if let spoken = lines.first(where: { $0.start <= time && time <= $0.end }) {
            return spoken.id
        }
        return (lines.last { $0.start <= time } ?? lines.first)?.id
    }

    /// The block a second falls in, by its number.
    ///
    /// `nil` when there are no blocks at all — a recording whose notes were
    /// never written — because a chapter rail with nothing in it has no row to
    /// pick out.
    static func block(at time: TimeInterval, in blocks: [NoteBlock]) -> Int? {
        guard !blocks.isEmpty else { return nil }

        let ordered = blocks.sorted { $0.number < $1.number }
        if let covering = ordered.first(where: { $0.start <= time && time <= $0.end }) {
            return covering.number
        }
        return (ordered.last { $0.start <= time } ?? ordered.first)?.number
    }

    // MARK: - A source chip

    /// What a source chip under a chat answer points at.
    ///
    /// A transcript chip carries its own second and brings the transcript
    /// forward at the line that was said then — which is what board 04
    /// describes it doing. A note chip carries a block number and brings the
    /// notes forward at that card.
    ///
    /// `nil` for a note that no longer exists. `ChatAnswering.turn(from:…)`
    /// already drops those, and this is the second place that has to agree,
    /// because the notes can be written again after the answer was.
    static func target(
        for reference: ChatReference,
        lines: [TranscriptLine],
        blocks: [NoteBlock]
    ) -> Target? {
        switch reference {
        case let .transcript(time):
            return line(at: time, in: lines).map(Target.line)
        case let .note(number):
            guard blocks.contains(where: { $0.number == number }) else { return nil }
            return .block(number)
        }
    }
}
