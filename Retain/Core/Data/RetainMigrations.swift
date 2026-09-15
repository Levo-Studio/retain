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

    /// Repairs a database created before a course could run in more than one
    /// term. See the migration itself — it exists because `v1.library` was
    /// edited after it had shipped, which is the one thing the note above says
    /// never to do.
    case coursesAcrossTerms = "v4.courses-across-terms"

    /// Where each part of a merged recording begins.
    ///
    /// Two lessons recorded by accident as two recordings become one, and the
    /// transcript then has to be able to say where the second one started —
    /// otherwise it reads as a single lecture with an unexplained jump in the
    /// middle of it. The rows are a fact about the recording, not transcript
    /// content, which is why they are not lines.
    case mergedRecordings = "v5.merged-recordings"
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
            //
            // **Both endpoints are nullable and nothing computes with them.**
            // The period is a caption under the term's name and no more: a
            // recording carries the term it was made in on its own row, so a
            // term with no period filters the library exactly as well as one
            // with a period. Somebody who does not know when their half-year
            // officially ends is not blocked by a field they cannot answer.
            try db.create(table: "term") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("startsOn", .datetime)
                t.column("endsOn", .datetime)
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

            // A course is **one subject, once**, and it carries no term.
            //
            // The same school subject runs in the winter half-year and in the
            // summer one, and it is the same course: renaming it renames it in
            // both, and its colour is its colour everywhere. Which terms it
            // runs in is `courseTerm`, and what was recorded in each of them is
            // the recording's own term — so a course spanning a year is one row
            // here rather than one row per half-year.
            try db.create(table: "course") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                // The index into the four colours the dialog offers, never a
                // hex string: the palette belongs to the design layer.
                t.column("color", .integer).notNull()
            }

            // Which terms a course runs in. Nothing else belongs on this row:
            // it is the membership and not a per-term copy of the course, which
            // is the whole point of the change — a name lives in one place.
            //
            // Cascading from **either** side, because a link to a course that
            // is gone, or to a term that is gone, is not a link. The course
            // survives losing a term and the term survives losing a course;
            // only the pairing goes.
            try db.create(table: "courseTerm") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("courseID", .integer)
                    .notNull()
                    .references("course", onDelete: .cascade)
                t.column("termID", .integer)
                    .notNull()
                    .references("term", onDelete: .cascade)
            }

            // A course is in a term or it is not — there is no "twice". The
            // uniqueness is in the schema rather than in a check the repository
            // makes first, so a second way of writing the row cannot get round
            // it. It is also the index the sidebar's read uses, since it leads
            // on the column that read groups by.
            try db.create(
                index: "courseTermOnCourseIDAndTermID",
                on: "courseTerm",
                columns: ["courseID", "termID"],
                unique: true
            )

            // The sidebar is "the courses of the selected term", which walks
            // the pair the other way round and would otherwise scan.
            try db.create(index: "courseTermOnTermID", on: "courseTerm", columns: ["termID"])

            // There is no lesson and no lesson number. A recording is what
            // happened, and `startedAt` carries the day **and the time of
            // day** — the column is not called `date` because it is not one:
            // two recordings on one afternoon are ordinary, so nothing indexes
            // or groups by the day alone.
            //
            // **A recording carries its term.** It cannot be derived: a term's
            // period is optional, so the date answers nothing, and a course now
            // runs in several terms, so the course answers nothing either. The
            // term is whichever one was current when the microphone opened, and
            // it stays that one — editing the term's period afterwards does not
            // move a single recording, which is exactly what a derived answer
            // would do.
            //
            // Cascading from the term as well as from the course, so that no
            // recording can point at a term that is gone. Both directions
            // remove recordings, which is why nothing in the interface deletes
            // a term.
            try db.create(table: "recording") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("courseID", .integer)
                    .notNull()
                    .references("course", onDelete: .cascade)
                t.column("termID", .integer)
                    .notNull()
                    .references("term", onDelete: .cascade)
                t.column("startedAt", .datetime).notNull()
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

            // The library table is "this course, in this term, newest first",
            // which is this index read backwards. Leading on `courseID` means
            // it still answers "everything in this course" for the sidebar's
            // count, without a second index for it.
            try db.create(
                index: "recordingOnCourseIDAndTermIDAndStartedAt",
                on: "recording",
                columns: ["courseID", "termID", "startedAt"]
            )

            // And the other way in: the term alone, which is the scope search
            // runs under and the one the cascade from a deleted term walks.
            try db.create(
                index: "recordingOnTermIDAndStartedAt",
                on: "recording",
                columns: ["termID", "startedAt"]
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
                // And where it ends, so a moment in the audio can be answered
                // with the note that covers it. The start alone only answers
                // the reverse question.
                t.column("endTime", .double).notNull()
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
                // What was marked, copied out of the block as it was marked.
                // The offsets alone are unrecoverable once the model has
                // written the block again; the text is what makes a highlight
                // re-anchorable, or at the very least showable. It costs a
                // column now and cannot be backfilled later.
                t.column("text", .text).notNull()
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

        // MARK: v4 — courses across terms, on a database that predates them

        // **This migration exists because the rule at the top of this file was
        // broken.** `v1.library` was edited in place when a course stopped
        // belonging to exactly one term: `courseTerm` was added to it,
        // `course.termID` removed, `termID` put on `recording`, and the term's
        // two dates made nullable. A database that had already recorded
        // `v1.library` as applied never ran a line of that — the migrator only
        // ever looks at the identifier — so every install that existed before
        // the change was left on the old shape with no way forward.
        //
        // What that looked like in the app: `courseTerm` and `recording.termID`
        // are in every query the library and the settings pane make, so each of
        // them threw `no such table` or `no such column`, and each of them was
        // called behind a `try?`. Creating a course did nothing. The course
        // list stayed empty. Deleting a term did nothing. Nothing said why.
        //
        // The repair is guarded on the old shape rather than on the migration
        // identifier, so a database created by the current `v1.library` — which
        // is every fresh install — passes straight through it.
        migrator.registerMigration(RetainMigration.coursesAcrossTerms.rawValue) { db in
            let courseColumns = try db.columns(in: "course").map(\.name)
            guard courseColumns.contains("termID") else { return }

            try repairCoursesAcrossTerms(db)
        }

        // MARK: v5 — merged recordings

        // One row per part of a recording that was merged out of several, and
        // no rows at all for a recording that was made in one sitting. The
        // offset is where that part begins inside the merged timeline, in
        // seconds, which is the unit every other time in Retain is in.
        //
        // `startedAt` is the part's own original start, kept because it is the
        // only thing that says a lesson was recorded in two sittings twenty
        // minutes apart rather than continuously — the offsets alone cannot,
        // since the gap between two recordings is not recorded audio.
        migrator.registerMigration(RetainMigration.mergedRecordings.rawValue) { db in
            try db.create(table: "recordingPart") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recordingID", .integer)
                    .notNull()
                    .indexed()
                    .references("recording", onDelete: .cascade)
                t.column("offset", .double).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("duration", .double).notNull().defaults(to: 0)
            }
        }

        return migrator
    }

    // MARK: - The v4 repair

    /// Moves a pre-`courseTerm` database onto the current shape, keeping every
    /// row.
    ///
    /// Three tables are recreated rather than altered, which is SQLite's own
    /// answer to changing a column's nullability or dropping one. It is safe
    /// here because the migrator runs with foreign keys disabled and checks
    /// them once at the end — `DatabaseMigrator.ForeignKeyChecks.deferred`,
    /// which is the default and has to stay it. With foreign keys on, dropping
    /// `recording` would cascade into every transcript line in the database.
    private static func repairCoursesAcrossTerms(_ db: Database) throws {
        // 1. The pairing table, filled from the term each course used to
        //    carry. One row per course, which is exactly what the old shape
        //    could express.
        try db.create(table: "courseTerm") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("courseID", .integer)
                .notNull()
                .references("course", onDelete: .cascade)
            t.column("termID", .integer)
                .notNull()
                .references("term", onDelete: .cascade)
        }
        try db.create(
            index: "courseTermOnCourseIDAndTermID",
            on: "courseTerm",
            columns: ["courseID", "termID"],
            unique: true
        )
        try db.create(index: "courseTermOnTermID", on: "courseTerm", columns: ["termID"])

        try db.execute(sql: "INSERT INTO courseTerm (courseID, termID) SELECT id, termID FROM course")

        // 2. The recording's own term, which used to be read through the
        //    course. It is copied across rather than derived from now on: a
        //    course runs in several terms, so the course no longer answers the
        //    question, and the recording's term is whichever one was current
        //    when the microphone opened.
        try db.create(table: "recordingNew") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("courseID", .integer).notNull().references("course", onDelete: .cascade)
            t.column("termID", .integer).notNull().references("term", onDelete: .cascade)
            t.column("startedAt", .datetime).notNull()
            t.column("duration", .double).notNull().defaults(to: 0)
            t.column("state", .text).notNull()
            t.column("topic", .text)
            t.column("filename", .text)
        }
        try db.execute(sql: """
            INSERT INTO recordingNew (id, courseID, termID, startedAt, duration, state, topic, filename)
            SELECT recording.id, recording.courseID, course.termID, recording.startedAt,
                   recording.duration, recording.state, recording.topic, recording.filename
            FROM recording JOIN course ON course.id = recording.courseID
            """)
        try db.drop(table: "recording")
        try db.rename(table: "recordingNew", to: "recording")
        try db.create(
            index: "recordingOnCourseIDAndTermIDAndStartedAt",
            on: "recording",
            columns: ["courseID", "termID", "startedAt"]
        )
        try db.create(
            index: "recordingOnTermIDAndStartedAt",
            on: "recording",
            columns: ["termID", "startedAt"]
        )

        // 3. The course without its term. One subject, once — the name and the
        //    colour now live in one row however many terms it runs in.
        try db.create(table: "courseNew") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("color", .integer).notNull()
        }
        try db.execute(sql: "INSERT INTO courseNew (id, name, color) SELECT id, name, color FROM course")
        try db.drop(table: "course")
        try db.rename(table: "courseNew", to: "course")

        // 4. The term's period, which used to be required. It is a caption and
        //    nothing computes with it, and somebody who does not know when
        //    their half-year officially ends should not be stopped by a field
        //    they cannot answer.
        try db.create(table: "termNew") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("title", .text).notNull()
            t.column("kind", .text).notNull()
            t.column("startsOn", .datetime)
            t.column("endsOn", .datetime)
            t.column("isCurrent", .boolean).notNull().defaults(to: false)
        }
        try db.execute(sql: """
            INSERT INTO termNew (id, title, kind, startsOn, endsOn, isCurrent)
            SELECT id, title, kind, startsOn, endsOn, isCurrent FROM term
            """)
        try db.drop(table: "term")
        try db.rename(table: "termNew", to: "term")
        try db.create(
            index: "termOnIsCurrent",
            on: "term",
            columns: ["isCurrent"],
            unique: true,
            condition: Column("isCurrent")
        )
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
    /// `v1.library`, `v2.recording-content` and `v4.courses-across-terms` have
    /// none, and not for want of writing one. Their only inverse is
    /// `DROP TABLE` over the tables that hold every recording the user has ever
    /// made — the transcripts, the
    /// notes, the highlights. That is data loss dressed up as a schema
    /// operation, it is exactly what this repository says to stop and ask
    /// about, and a convenience method for it would eventually be called by
    /// something that should not have. The way back from either is the file
    /// backup, not a function in here.
    static func rollBack(_ migration: RetainMigration, in db: Database) throws {
        switch migration {
        case .library, .recordingContent, .coursesAcrossTerms:
            throw RetainDatabaseError.migrationHasNoRollback(migration.rawValue)

        case .mergedRecordings:
            // The only migration here with a real inverse: the table holds
            // where the parts of a merged recording begin, and dropping it
            // loses that and nothing else. The merge itself is not undone by
            // it and never could be — the recordings it joined are gone.
            try db.drop(table: "recordingPart")
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: [migration.rawValue]
            )

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
