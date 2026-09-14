import Foundation

/// The three repositories a running lecture writes through, in one value.
///
/// It exists so `LectureSession` takes one dependency instead of three, and so
/// that a session built without a database — a preview, a test that only cares
/// about phases — is a session with `nil` here rather than three optionals and
/// a rule about which of them may be missing.
nonisolated struct LectureStore: Sendable {

    let library: LibraryRepository
    let transcript: TranscriptRepository
    let notes: NoteRepository

    /// Kept alongside the repositories because the detail and library models
    /// build their own — they read across four tables at once, and handing them
    /// four repositories would be handing them the database the long way round.
    let database: RetainDatabase

    init(_ database: RetainDatabase) {
        self.database = database
        library = LibraryRepository(database)
        transcript = TranscriptRepository(database)
        notes = NoteRepository(database)
    }
}
