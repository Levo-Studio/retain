import Foundation
import GRDB

/// The migrations, in the order they run.
///
/// The raw value is the identifier written into `grdb_migrations`, so it is
/// part of every database that has ever been opened. **Renaming one would make
/// an existing database run that migration a second time.** They are
/// append-only: a shipped migration is never edited, a mistake in one is
/// corrected by the next.
nonisolated enum RetainMigration: String, CaseIterable, Sendable {

    /// Terms, courses, recordings — the three the library is drawn from.
    case library = "v1.library"

    /// What a recording holds: transcript lines, annotations, notes,
    /// highlights.
    case recordingContent = "v2.recording-content"

    /// The FTS5 indexes over transcript lines, notes and annotations.
    case search = "v3.search"
}

// MARK: -

nonisolated enum RetainMigrations {

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // MARK: v1 — the library

        migrator.registerMigration(RetainMigration.library.rawValue) { db in
            // A term is the top-level filter. The period is two month-granular
            // endpoints because the dialog offers months, not days, and `kind`
            // sits on the row rather than in a setting so that switching from
            // half-years to semesters does not re-label the terms already
            // recorded.
            try db.create(table: "term") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("startsOn", .datetime).notNull()
                t.column("endsOn", .datetime).notNull()
                t.column("isCurrent", .boolean).notNull().defaults(to: false)
            }

            // "Shown as selected at the top" is a property of the set, not of
            // one row, so the database enforces it rather than trusting every
            // future caller to clear the old one first. A partial unique index
            // permits any number of `false` and exactly one `true`.
            try db.create(
                index: "termOnIsCurrent",
                on: "term",
                columns: ["isCurrent"],
                unique: true,
                condition: Column("isCurrent")
            )

            // A course belongs to exactly one term. A course that runs across
            // two terms is two rows — that is what the sidebar draws, and it is
            // what makes the term a filter rather than a label.
            try db.create(table: "course") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("termID", .integer)
                    .notNull()
                    .references("term", onDelete: .cascade)
                t.column("name", .text).notNull()
                // The index into the four colours the dialog offers, never a
                // hex string: the palette belongs to the design layer.
                t.column("color", .integer).notNull()
            }

            // The sidebar is "the courses of the selected term" and nothing
            // else, so this is the one read the table exists for.
            try db.create(index: "courseOnTermID", on: "course", columns: ["termID"])

            // There is no lesson and no lesson number. A recording is what
            // happened, and `date` carries the day **and the time of day**:
            // two recordings on one afternoon are ordinary, so nothing indexes
            // or groups by the day alone.
            try db.create(table: "recording") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("courseID", .integer)
                    .notNull()
                    .references("course", onDelete: .cascade)
                t.column("date", .datetime).notNull()
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("state", .text).notNull()
                // Null until the model reads a topic out of the transcript,
                // and null forever if it never runs.
                t.column("topic", .text)
                // The file name inside `RecordingStore.directory`, never a
                // path: a path would carry the user's home directory into the
                // database and would break when the folder moves.
                t.column("filename", .text)
            }

            // The table is drawn newest first, which is this index read
            // backwards, and it is the lookup for a course's recordings.
            try db.create(
                index: "recordingOnCourseIDAndDate",
                on: "recording",
                columns: ["courseID", "date"]
            )
        }

        // MARK: v2 — what a recording holds

        migrator.registerMigration(RetainMigration.recordingContent.rawValue) { db in
            try db.create(table: "transcriptLine") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recordingID", .integer)
                    .notNull()
                    .references("recording", onDelete: .cascade)
                // `TranscriptLine.id`, kept so a line holds its identity across
                // a reload and the transcript view does not rebuild every row
                // when one line changes.
                t.column("uuid", .blob).notNull()
                t.column("startTime", .double).notNull()
                t.column("endTime", .double).notNull()
                t.column("text", .text).notNull()
                t.column("speaker", .text).notNull()
                // True while the line came from the live pass. Those lines are
                // feedback and get replaced wholesale by the batch pass.
                t.column("isProvisional", .boolean).notNull().defaults(to: false)
            }

            // Every read of a transcript is "the lines of this recording, in
            // time order", and so is every seek.
            try db.create(
                index: "transcriptLineOnRecordingIDAndStartTime",
                on: "transcriptLine",
                columns: ["recordingID", "startTime"]
            )

            // What ⌘⇧M writes while the lecture runs: typed, anchored to a
            // second, and fed to the model with the block it falls in.
            try db.create(table: "annotation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recordingID", .integer)
                    .notNull()
                    .references("recording", onDelete: .cascade)
                t.column("time", .double).notNull()
                // Null when the user marked the spot without typing anything.
                t.column("note", .text)
            }

            try db.create(
                index: "annotationOnRecordingIDAndTime",
                on: "annotation",
                columns: ["recordingID", "time"]
            )

            // The seam for the summarisation layer.
            //
            // One Markdown string per block, because that is what the model
            // writes — a heading, a paragraph, bullets, an emphasised term.
            // The chapters rail is read back out of the headings rather than
            // stored beside them, so there is one place a note lives and no
            // second copy to fall out of step.
            try db.create(table: "noteBlock") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recordingID", .integer)
                    .notNull()
                    .references("recording", onDelete: .cascade)
                // Reading order, which is not always time order once a reduce
                // has merged two stretches of the lecture into one note.
                t.column("position", .integer).notNull()
                // Where the block starts in the recording. The chapters rail
                // draws this as its timestamp and seeks to it.
                t.column("startTime", .double).notNull()
                t.column("markdown", .text).notNull()
            }

            try db.create(
                index: "noteBlockOnRecordingIDAndPosition",
                on: "noteBlock",
                columns: ["recordingID", "position"]
            )

            // A passage of the notes the user marked, during the lecture or
            // after it. It hangs off a note block and a byte range inside that
            // block's Markdown, not off a moment in the audio.
            //
            // `recordingID` could be reached through `noteBlockID`; it is here
            // because "the highlights in this recording" is the question the
            // interface actually asks, and because the cascade from a deleted
            // recording is then direct.
            try db.create(table: "highlight") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recordingID", .integer)
                    .notNull()
                    .references("recording", onDelete: .cascade)
                t.column("noteBlockID", .integer)
                    .notNull()
                    .references("noteBlock", onDelete: .cascade)
                // UTF-8 byte offsets, half open. See `Highlight`.
                t.column("startOffset", .integer).notNull()
                t.column("endOffset", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "highlightOnNoteBlockIDAndStartOffset",
                on: "highlight",
                columns: ["noteBlockID", "startOffset"]
            )

            try db.create(index: "highlightOnRecordingID", on: "highlight", columns: ["recordingID"])
        }

        // MARK: v3 — search

        migrator.registerMigration(RetainMigration.search.rawValue) { db in
            try createSearchIndexes(db)
        }

        return migrator
    }

    // MARK: - Search indexes

    /// The three FTS5 indexes and the triggers that keep them current.
    ///
    /// **External content**, so an index stores its own inverted terms but not
    /// a second copy of the text — the row in `transcriptLine`, `noteBlock` or
    /// `annotation` stays the only one. A contentless-but-copied FTS table
    /// would double every transcript on disk and, worse, give two places where
    /// the same sentence is written and one of them can be stale. The price is
    /// that SQLite does not update the index by itself, which is what the three
    /// triggers per table are for: insert, delete, and update-as-delete-then-
    /// insert.
    ///
    /// `remove_diacritics 2` folds "Übung" to "ubung" and "Bélády" to "belady"
    /// at index time and at query time alike, so a German transcript is found
    /// by someone typing without the umlaut — and still found by someone typing
    /// with it. Version 2 and not the legacy 1: 1 leaves any character built
    /// from more than one code point alone. It does not touch "ß", which stays
    /// its own letter in both the index and the query, so the two agree.
    private static func createSearchIndexes(_ db: Database) throws {
        try db.create(virtualTable: "transcriptLineSearch", using: FTS5()) { t in
            t.synchronize(withTable: "transcriptLine")
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("text")
        }

        // The Markdown is indexed as it is written. The punctuation that makes
        // it Markdown — `#`, `*`, `-` — is a token separator to unicode61, so
        // a heading is searched as its words and nobody has to strip anything
        // first.
        try db.create(virtualTable: "noteBlockSearch", using: FTS5()) { t in
            t.synchronize(withTable: "noteBlock")
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("markdown")
        }

        // Annotations are the one thing in the database the user typed
        // themselves, which makes them the most likely thing they will go
        // looking for.
        try db.create(virtualTable: "annotationSearch", using: FTS5()) { t in
            t.synchronize(withTable: "annotation")
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("note")
        }
    }

    // MARK: - Rolling back

    /// Undoes one migration, where undoing it costs nothing.
    ///
    /// Only `v3.search` has a rollback. It drops three FTS5 tables and their
    /// triggers, and **no user content is lost**: an external-content index
    /// holds nothing but terms derived from rows that stay exactly where they
    /// are, and re-running the migration rebuilds it from those rows.
    ///
    /// `v1.library` and `v2.recording-content` have none, and not for want of
    /// writing one. Their only inverse is `DROP TABLE` over the tables that
    /// hold every recording the user has ever made — the transcripts, the
    /// notes, the highlights. That is data loss dressed up as a schema
    /// operation, it is exactly what this repository says to stop and ask
    /// about, and a convenience method for it would eventually be called by
    /// something that should not have. The way back from either is the file
    /// backup, not a function in here.
    static func rollBack(_ migration: RetainMigration, in db: Database) throws {
        switch migration {
        case .library, .recordingContent:
            throw RetainDatabaseError.migrationHasNoRollback(migration.rawValue)

        case .search:
            for table in ["transcriptLineSearch", "noteBlockSearch", "annotationSearch"] {
                try db.drop(table: table)
                // SQLite drops these with the content table but not with the
                // FTS table, and a leftover trigger writing into a table that
                // is gone fails every later insert into the content table.
                try db.dropFTS5SynchronizationTriggers(forTable: table)
            }

            // Without this the migrator still counts the migration as applied
            // and would never put the index back.
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: [migration.rawValue]
            )
        }
    }
}

// MARK: -

nonisolated extension RetainDatabase {

    /// Undoes one migration. See `RetainMigrations.rollBack(_:in:)` — most of
    /// them have no rollback and throw.
    func rollBack(_ migration: RetainMigration) throws {
        try writer.write { try RetainMigrations.rollBack(migration, in: $0) }
    }
}
