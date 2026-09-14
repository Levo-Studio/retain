import Foundation

/// Reads the chapter rail out of the note blocks.
///
/// Nothing stores a chapter. The rail board 03 draws is the heading of each
/// note block beside the minute that block started, and both halves are already
/// known: the heading because the card's Markdown carries it, the minute
/// because the block was cut out of the transcript at a known second.
///
/// Deriving it rather than storing it has one consequence worth stating: the
/// rail cannot disagree with the notes. A stored chapter list survives the
/// notes being rewritten and then points at headings that are no longer there.
nonisolated enum NoteChapters {

    /// - Parameters:
    ///   - blocks: the cards, in order.
    ///   - markers: everything the user marked, for the amber dot.
    static func entries(from blocks: [NoteBlock], markers: [RecordingMarker] = []) -> [NoteChapter] {
        blocks.compactMap { block in
            // A card whose Markdown has no heading has no row. It is the case
            // that breaks the rail — a model that answered with a bare
            // paragraph — and the answer is a rail one row short rather than a
            // row with an empty label in it.
            guard let title = block.heading else { return nil }

            return NoteChapter(
                blockNumber: block.number,
                title: title,
                time: block.start,
                hasMarker: markers.contains { $0.time >= block.start && $0.time <= block.end }
            )
        }
    }
}
