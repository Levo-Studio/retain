import Foundation
import GRDB

/// One course in the sidebar, with the two numbers drawn beside it.
///
/// They come out of the same grouped query as the course itself: asking for the
/// courses and then counting each one's recordings is one statement per course,
/// and the sidebar has a row per course.
///
/// **The two numbers are the selected term's, not the course's.** A course runs
/// in several terms and its recordings are filed under the term they were made
/// in, so "9 recordings · 13 h 24 min" beside Computer science in the winter
/// half-year counts winter and nothing else. That is the whole point of the
/// library: pick another term at the top and the same course shows that term's
/// work instead.
nonisolated struct CourseListing: Identifiable, Hashable, Sendable {

    var course: Course
    /// Drawn at the right of the sidebar row, and in the course header.
    var recordingCount: Int
    /// Seconds over every recording in the course **in that term** —
    /// "13 h 24 min" in the header.
    var totalDuration: TimeInterval

    var id: Int64? { course.id }
}

// MARK: -

/// Terms, courses and recordings: everything the library window is drawn from.
///
/// Reads are ordered the way the design draws them, so a view binds to the
/// result without re-sorting it.
nonisolated struct LibraryRepository: Sendable {

    private let database: RetainDatabase

    init(_ database: RetainDatabase) {
        self.database = database
    }

    // MARK: - Terms

    /// Newest first, which is the order the picker opens in.
    ///
    /// A term with no period has no place on that line, so SQLite's own answer
    /// is taken rather than invented: `NULL` is the smallest value there is, so
    /// descending puts the periodless terms after the dated ones, and `id`
    /// orders those among themselves — most recently named first, which is the
    /// only sense in which one of them is newer than another.
    func terms() async throws -> [Term] {
        try await database.writer.read { db in
            try Term
                .order(Term.Columns.startsOn.desc, Term.Columns.id.desc)
                .fetchAll(db)
        }
    }

    /// The term the library opens on, or `nil` before the user has named one.
    func currentTerm() async throws -> Term? {
        try await database.writer.read { db in
            try Term.filter(Term.Columns.isCurrent).fetchOne(db)
        }
    }

    func term(_ id: Int64) async throws -> Term? {
        try await database.writer.read { try Term.fetchOne($0, key: id) }
    }

    /// Inserts a term that has no id yet, updates one that has.
    @discardableResult
    func save(_ term: Term) async throws -> Term {
        try await database.writer.write { db in
            var stored = term
            try stored.save(db)
            return stored
        }
    }

    /// Makes one term the one the picker opens on, and no other.
    ///
    /// Both statements are in one transaction because the schema allows exactly
    /// one current term: between them there is a moment with none, and there
    /// must never be a moment with two.
    func makeCurrent(_ termID: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE term SET isCurrent = 0 WHERE isCurrent AND id <> ?",
                arguments: [termID]
            )
            try db.execute(
                sql: "UPDATE term SET isCurrent = 1 WHERE id = ?",
                arguments: [termID]
            )
        }
    }

    /// What deleting a term would take with it.
    ///
    /// Read before the confirmation rather than after, because this is the one
    /// action in Retain that destroys work: a term's recordings cascade with
    /// it, and a recording is a lecture somebody sat through. The dialog says
    /// these numbers out loud so nobody agrees to it by reflex.
    func deletionImpact(of termID: Int64) async throws -> TermDeletion {
        try await database.writer.read { db in
            let recordings = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM recording WHERE termID = ?",
                arguments: [termID]
            ) ?? 0

            // A course that runs in another term survives the deletion with
            // that term's recordings intact. One that ran only here has nowhere
            // left to be, and every list of courses in the app is a term's
            // list — so it would become a row nobody can reach.
            let orphanedCourses = try String.fetchAll(
                db,
                sql: """
                    SELECT course.name FROM course
                    JOIN courseTerm ON courseTerm.courseID = course.id
                    WHERE courseTerm.termID = ?
                      AND NOT EXISTS (
                        SELECT 1 FROM courseTerm AS other
                        WHERE other.courseID = course.id AND other.termID <> ?
                      )
                    ORDER BY course.name
                    """,
                arguments: [termID, termID]
            )

            return TermDeletion(recordings: recordings, coursesLost: orphanedCourses)
        }
    }

    /// Deletes a term, everything recorded in it, and any course left with
    /// nowhere to be.
    ///
    /// One transaction. The cascade takes the recordings and the course links;
    /// what it cannot know is that a course whose last term this was has become
    /// unreachable, so that is swept here rather than left behind.
    ///
    /// If the deleted term was the current one, the most recent survivor takes
    /// its place — a library with terms but none of them current opens on
    /// nothing and looks broken.
    func delete(term termID: Int64) async throws {
        try await database.writer.write { db in
            let wasCurrent = try Bool.fetchOne(
                db,
                sql: "SELECT isCurrent FROM term WHERE id = ?",
                arguments: [termID]
            ) ?? false

            try db.execute(sql: "DELETE FROM term WHERE id = ?", arguments: [termID])

            try db.execute(sql: """
                DELETE FROM course
                WHERE NOT EXISTS (SELECT 1 FROM courseTerm WHERE courseTerm.courseID = course.id)
                """)

            if wasCurrent {
                try db.execute(sql: """
                    UPDATE term SET isCurrent = 1
                    WHERE id = (SELECT id FROM term ORDER BY startsOn DESC, id DESC LIMIT 1)
                    """)
            }
        }
    }

    // MARK: - Courses

    /// The courses of one term, in the order they were created, each with the
    /// numbers the sidebar draws.
    ///
    /// Which courses is the join table; **how many recordings is the term
    /// again**, on the join condition rather than in a `WHERE`. That is the
    /// difference between a course that is in this term and a course whose
    /// recordings are in this term: the first decides whether the row is drawn
    /// at all, the second what number sits beside it. On a `WHERE` the second
    /// would turn the outer join inner and a course with nothing recorded in
    /// this term would vanish from the sidebar instead of reading zero.
    func courses(in termID: Int64) async throws -> [CourseListing] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT course.*,
                       COUNT(recording.id) AS recordingCount,
                       COALESCE(SUM(recording.duration), 0) AS totalDuration
                FROM course
                JOIN courseTerm ON courseTerm.courseID = course.id
                LEFT JOIN recording
                       ON recording.courseID = course.id
                      AND recording.termID = courseTerm.termID
                WHERE courseTerm.termID = ?
                GROUP BY course.id
                ORDER BY course.id
                """, arguments: [termID])

            return try rows.map { row in
                CourseListing(
                    course: try Course(row: row),
                    recordingCount: row["recordingCount"],
                    totalDuration: row["totalDuration"]
                )
            }
        }
    }

    func course(_ id: Int64) async throws -> Course? {
        try await database.writer.read { try Course.fetchOne($0, key: id) }
    }

    /// The terms a course runs in, newest first — the same order the picker
    /// lists them in.
    func terms(of courseID: Int64) async throws -> [Term] {
        try await database.writer.read { db in
            try Term.fetchAll(db, sql: """
                SELECT term.*
                FROM term
                JOIN courseTerm ON courseTerm.termID = term.id
                WHERE courseTerm.courseID = ?
                ORDER BY term.startsOn DESC, term.id DESC
                """, arguments: [courseID])
        }
    }

    /// Writes a course and the terms it runs in, together.
    ///
    /// **A course in no term is refused.** It would be a row nothing can ever
    /// reach: the sidebar is a term's courses, the popover's picker is the
    /// current term's courses, and a subject that appears in neither is not a
    /// course, it is a leak. The dialog refuses it too — this is the second
    /// answer to the same question, because the repository is reachable without
    /// the dialog.
    ///
    /// One transaction, so a course never exists for a moment with no term.
    @discardableResult
    func create(_ course: Course, in termIDs: Set<Int64>) async throws -> Course {
        guard !termIDs.isEmpty else { throw RetainDatabaseError.courseWithoutTerm }

        return try await database.writer.write { db in
            var stored = course
            try stored.insert(db)
            guard let courseID = stored.id else { throw RetainDatabaseError.unsavedRow }

            // Sorted so two runs write the rows in the same order, which keeps
            // a failing assertion about them readable.
            for termID in termIDs.sorted() {
                var link = CourseTerm(courseID: courseID, termID: termID)
                try link.insert(db)
            }
            return stored
        }
    }

    /// Replaces the terms a course runs in.
    ///
    /// A delete and an insert rather than a diff: the set is at most a handful
    /// of rows, and the pairs carry nothing of their own that could be lost by
    /// writing them again. Recordings are untouched — they hold their own term
    /// and are not reachable from these rows.
    func setTerms(of courseID: Int64, to termIDs: Set<Int64>) async throws {
        guard !termIDs.isEmpty else { throw RetainDatabaseError.courseWithoutTerm }

        try await database.writer.write { db in
            try CourseTerm
                .filter(CourseTerm.Columns.courseID == courseID)
                .deleteAll(db)

            for termID in termIDs.sorted() {
                var link = CourseTerm(courseID: courseID, termID: termID)
                try link.insert(db)
            }
        }
    }

    /// Renames a course, or repaints it. **Not** where its terms change — see
    /// `setTerms(of:to:)` — because a course row no longer carries one.
    @discardableResult
    func save(_ course: Course) async throws -> Course {
        try await database.writer.write { db in
            var stored = course
            try stored.save(db)
            return stored
        }
    }

    // MARK: - Recordings

    /// One course in one term, newest first — the way the table is drawn.
    ///
    /// **Both, always.** A course runs in several terms and the library is
    /// looking at one of them: the course alone would pour last summer's
    /// recordings into this winter's table, which is precisely what the term
    /// picker at the top of board 05 exists to prevent.
    ///
    /// By date **and** time: two recordings on one afternoon are ordinary, and
    /// sorting by the day alone would put them in whichever order the rows
    /// happened to be written.
    func recordings(in courseID: Int64, during termID: Int64) async throws -> [Recording] {
        try await database.writer.read { db in
            try Recording
                .filter(Recording.Columns.courseID == courseID)
                .filter(Recording.Columns.termID == termID)
                .order(Recording.Columns.startedAt.desc, Recording.Columns.id.desc)
                .fetchAll(db)
        }
    }

    /// Every recording that still names a file on disk.
    ///
    /// The launch sweep's whole question, asked once. It used to walk terms,
    /// then each term's courses, then each course's recordings — a scan of the
    /// entire library to find a set that on a settled install is empty or has
    /// one row in it, and one that now needs both a course and a term to ask
    /// for at all.
    ///
    /// The name is cleared when the audio goes, so this is exactly the
    /// candidate set and nothing else.
    func recordingsWithAudio() async throws -> [Recording] {
        try await database.writer.read { db in
            try Recording
                .filter(Recording.Columns.filename != nil)
                .order(Recording.Columns.startedAt)
                .fetchAll(db)
        }
    }

    func recording(_ id: Int64) async throws -> Recording? {
        try await database.writer.read { try Recording.fetchOne($0, key: id) }
    }

    @discardableResult
    func save(_ recording: Recording) async throws -> Recording {
        try await database.writer.write { db in
            var stored = recording
            try stored.save(db)
            return stored
        }
    }

    /// Opens a row for a recording that is starting now.
    ///
    /// `startedAt` is the moment the microphone opened, to the second, and it
    /// is what the recording is identified by from here on. There is nothing to
    /// number and nothing to name.
    ///
    /// The term is taken rather than worked out. It is the one that was current
    /// when the microphone opened, and once written it does not move: a term's
    /// period can be edited afterwards without a single recording changing
    /// hands, and a course that is added to another term next year does not
    /// drag this recording into it.
    @discardableResult
    func startRecording(
        in courseID: Int64,
        during termID: Int64,
        at startedAt: Date = .now,
        filename: String? = nil
    ) async throws -> Recording {
        try await database.writer.write { db in
            var recording = Recording(
                courseID: courseID,
                termID: termID,
                startedAt: startedAt,
                state: .recording,
                filename: filename
            )
            try recording.insert(db)
            return recording
        }
    }
}
