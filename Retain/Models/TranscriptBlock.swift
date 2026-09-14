import Foundation

/// One stretch of a recording that gets summarised on its own.
///
/// A block is the unit the live notes are made of: it closes after about three
/// minutes of speech, or early when the user marks something, and a small model
/// then writes a single note card from it while the recording carries on.
nonisolated struct TranscriptBlock: Identifiable, Hashable, Sendable {

    /// Why the block ended. Carried because it is the difference between a card
    /// that appeared on its own and one the user asked for, and because a test
    /// that can only see the line counts cannot tell a boundary that fired for
    /// the right reason from one that fired for the wrong one.
    enum Closing: Hashable, Sendable {

        /// Three minutes of speech had accumulated.
        case speechBudget

        /// The user pressed `⌘⇧M`.
        case marker

        /// The recording stopped.
        case endOfRecording

        /// Still filling. The design draws this one dim, with "schreibt …"
        /// beside the heading.
        case open
    }

    /// One-based, in order. The design draws it zero-padded ("01"), and it is
    /// what a note block's number refers to.
    let number: Int

    let lines: [TranscriptLine]

    /// Everything the user marked inside this block, in time order.
    var markers: [RecordingMarker]

    let closing: Closing

    var id: Int { number }

    var start: TimeInterval { lines.first?.start ?? 0 }
    var end: TimeInterval { lines.last?.end ?? 0 }

    /// Seconds of speech, not seconds of wall clock. See `BlockBoundaries`.
    var speechDuration: TimeInterval {
        lines.reduce(0) { $0 + max(0, $1.duration) }
    }

    var isOpen: Bool { closing == .open }

    /// The block as one string.
    var text: String {
        lines.map(\.text).joined(separator: " ")
    }
}
