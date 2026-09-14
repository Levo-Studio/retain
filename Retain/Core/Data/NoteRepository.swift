import Foundation
import GRDB

/// The written-out notes of a recording and the passages marked in them —
/// **the seam for the summarisation layer**.
///
/// It takes Markdown, a position and a time, not a model type: what a note
/// block is on the way out of the reduce belongs to `Core/LLM/` and
/// `Pipeline/`, and storing it must not become a second definition of it.
///
/// The chapters rail is these same rows: its timestamps are `startTime` and its
/// titles are the headings read back out of the Markdown.
nonisolated struct NoteRepository: Sendable {

    private let database: RetainDatabase

    init(_ database: RetainDatabase) {
        self.database = database
    }

    // MARK: - Blocks

    /// In reading order, which is the order the notes pane draws them.
    func blocks(for recordingID: Int64) async throws -> [StoredNoteBlock] {
        try await database.writer.read { db in
            try StoredNoteBlock
                .filter(StoredNoteBlock.Columns.recordingID == recordingID)
                .order(StoredNoteBlock.Columns.position, StoredNoteBlock.Columns.id)
                .fetchAll(db)
        }
    }

    /// Appends one block as it closes during the lecture.
    ///
    /// A block closes every few minutes while the recording runs, and the card
    /// is on screen before this is called — the write is what makes it survive
    /// the lecture.
    @discardableResult
    func append(_ block: StoredNoteBlock, to recordingID: Int64) async throws -> StoredNoteBlock {
        try await database.writer.write { db in
            var stored = block
            stored.id = nil
            stored.recordingID = recordingID
            try stored.insert(db)
            return stored
        }
    }

    /// Replaces every note of a recording.
    ///
    /// The reduce produces the notes of a recording as a whole, not block by
    /// block, so this is the shape the writing side actually has. One
    /// transaction: a half-written set of notes is a recording that reads as if
    /// the model stopped in the middle.
    ///
    /// **It takes the highlights with it.** A highlight is a byte range into
    /// the Markdown of a block that no longer exists, and there is no way to
    /// carry it across a text the model rewrote from scratch. Anything that
    /// re-summarises a recording the user has already marked up is therefore
    /// throwing their marks away, which is a decision for the owner and not a
    /// thing to paper over here.
    func replaceBlocks(_ blocks: [StoredNoteBlock], for recordingID: Int64) async throws {
        try await database.writer.write { db in
            try StoredNoteBlock
                .filter(StoredNoteBlock.Columns.recordingID == recordingID)
                .deleteAll(db)

            for block in blocks {
                // The caller numbers the blocks; the recording is taken from
                // the argument so a block cannot be written into the wrong one
                // by a mistake in the caller.
                var stored = block
                stored.id = nil
                stored.recordingID = recordingID
                try stored.insert(db)
            }
        }
    }

    // MARK: - Highlights

    /// Every highlight in a recording, block by block and in reading order
    /// inside each.
    func highlights(for recordingID: Int64) async throws -> [Highlight] {
        try await database.writer.read { db in
            try Highlight
                .filter(Highlight.Columns.recordingID == recordingID)
                .order(Highlight.Columns.noteBlockID, Highlight.Columns.startOffset)
                .fetchAll(db)
        }
    }

    func highlights(inBlock noteBlockID: Int64) async throws -> [Highlight] {
        try await database.writer.read { db in
            try Highlight
                .filter(Highlight.Columns.noteBlockID == noteBlockID)
                .order(Highlight.Columns.startOffset)
                .fetchAll(db)
        }
    }

    /// Marks a passage of one block.
    ///
    /// The range is in UTF-8 bytes and half open, and it is read off the block
    /// that is actually stored — `block` carries its own id and recording, so a
    /// highlight cannot be filed against a block the user was not looking at.
    @discardableResult
    func highlight(
        _ block: StoredNoteBlock,
        from startOffset: Int,
        to endOffset: Int,
        at createdAt: Date = .now
    ) async throws -> Highlight {
        guard let noteBlockID = block.id else {
            throw RetainDatabaseError.unsavedRow
        }

        return try await database.writer.write { db in
            var highlight = Highlight(
                recordingID: block.recordingID,
                noteBlockID: noteBlockID,
                startOffset: startOffset,
                endOffset: endOffset,
                createdAt: createdAt
            )
            try highlight.insert(db)
            return highlight
        }
    }

    /// Takes one highlight back off. The notes themselves are untouched.
    func removeHighlight(_ id: Int64) async throws {
        try await database.writer.write { db in
            _ = try Highlight.deleteOne(db, key: id)
        }
    }
}
