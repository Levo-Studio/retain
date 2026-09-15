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

    /// The store behind this repository, for a caller that wants to be told
    /// when it changes rather than to read it. See `LibraryChanges`.
    var changes: AsyncValueObservation<Int64> { LibraryChanges.stream(in: database) }

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

    // MARK: - Merging

    /// Joins several recordings of one lesson into one, in the order they
    /// happened.
    ///
    /// The microphone gets stopped at a break and started again afterwards, and
    /// what was one lesson is two rows in the library with half a transcript
    /// each. The notes are then written twice, each from half the material, and
    /// neither is the lesson.
    ///
    /// **The earliest recording survives and the others are emptied into it.**
    /// Not a new row: the survivor keeps its id, so every highlight, every
    /// chapter and every window already open on it stay pointed at something
    /// that exists. Its start time is therefore the lesson's start time, which
    /// is the answer somebody looking for that lesson in the library will have
    /// in their head.
    ///
    /// Times are laid end to end. Part two's transcript moves forward by
    /// everything before it, so the merged timeline is continuous even where
    /// the afternoon was not — the gap between two sittings is not recorded
    /// audio and there is nothing to lay in it. `recordingPart` keeps each
    /// part's own start, which is the only thing that can say the second half
    /// began twenty minutes later.
    ///
    /// The notes are **not** merged. Two sets of notes over two halves do not
    /// add up to notes over the lesson, and stitching them would read as one
    /// document written by two people who had not met. They are dropped, the
    /// recording is left ready to be analysed again, and the model is given the
    /// whole transcript once — which is the same thing that happens to any
    /// recording whose notes are rewritten.
    ///
    /// - Returns: the merged recording, and the file names of any audio the
    ///   emptied rows still had, for the caller to unlink.
    @discardableResult
    func merge(recordings ids: [Int64]) async throws -> (recording: Recording, orphanedAudio: [String]) {
        try await database.writer.write { db in
            let recordings = try Recording
                .filter(ids.contains(Recording.Columns.id))
                .order(Recording.Columns.startedAt, Recording.Columns.id)
                .fetchAll(db)

            guard recordings.count > 1 else { throw RetainDatabaseError.nothingToMerge }

            // A lecture that is still being recorded is not a lecture to move
            // rows out of: the microphone is open and the writer is appending
            // to it.
            guard !recordings.contains(where: { $0.state == .recording }) else {
                throw RetainDatabaseError.cannotMergeWhileRecording
            }

            guard var survivor = recordings.first, let survivorID = survivor.id else {
                throw RetainDatabaseError.nothingToMerge
            }

            // Every part, including the survivor's own, so a merged recording
            // always says where all of it came from rather than only where the
            // joins are.
            var offset: TimeInterval = 0
            var orphanedAudio: [String] = []

            for recording in recordings {
                guard let id = recording.id else { continue }

                var part = RecordingPart(
                    recordingID: survivorID,
                    offset: offset,
                    startedAt: recording.startedAt,
                    duration: recording.duration
                )
                try part.insert(db)

                if id != survivorID {
                    try db.execute(
                        sql: """
                            UPDATE transcriptLine
                            SET recordingID = ?, startTime = startTime + ?, endTime = endTime + ?
                            WHERE recordingID = ?
                            """,
                        arguments: [survivorID, offset, offset, id]
                    )
                    try db.execute(
                        sql: "UPDATE annotation SET recordingID = ?, time = time + ? WHERE recordingID = ?",
                        arguments: [survivorID, offset, id]
                    )
                    if let filename = recording.filename, !filename.isEmpty {
                        orphanedAudio.append(filename)
                    }
                    // Cascades to whatever is left under it: the notes and the
                    // highlights, which are deliberately not carried over.
                    try db.execute(sql: "DELETE FROM recording WHERE id = ?", arguments: [id])
                }

                offset += recording.duration
            }

            // The survivor's own notes go too. See the note above: two sets
            // over two halves are not notes over the lesson.
            try db.execute(sql: "DELETE FROM noteBlock WHERE recordingID = ?", arguments: [survivorID])

            survivor.duration = offset
            survivor.topic = nil
            survivor.state = .done
            try survivor.update(db)

            return (survivor, orphanedAudio)
        }
    }

    /// Where the parts of a merged recording begin, in order. Empty for a
    /// recording made in one sitting, which is the ordinary case.
    func parts(of recordingID: Int64) async throws -> [RecordingPart] {
        try await database.writer.read { db in
            try RecordingPart
                .filter(RecordingPart.Columns.recordingID == recordingID)
                .order(RecordingPart.Columns.offset)
                .fetchAll(db)
        }
    }

    /// What deleting one recording would take with it.
    ///
    /// Counted before the confirmation rather than after, for the same reason
    /// as a term's: this is the only copy. The audio is usually already gone by
    /// the time a recording is in the library — it is deleted as soon as it has
    /// been transcribed — so what is at stake is the transcript, the notes, and
    /// the marks the user typed during the lecture.
    func deletionImpact(ofRecording recordingID: Int64) async throws -> RecordingDeletion {
        try await database.writer.read { db in
            func count(_ table: String) throws -> Int {
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(table) WHERE recordingID = ?",
                    arguments: [recordingID]
                ) ?? 0
            }

            let row = try Row.fetchOne(
                db,
                sql: "SELECT state, filename FROM recording WHERE id = ?",
                arguments: [recordingID]
            )

            return RecordingDeletion(
                transcriptLines: try count("transcriptLine"),
                noteBlocks: try count("noteBlock"),
                annotations: try count("annotation"),
                highlights: try count("highlight"),
                hasAudio: (row?["filename"] as String?).map { !$0.isEmpty } ?? false,
                isRecording: (row?["state"] as String?) == RecordingState.recording.rawValue
            )
        }
    }

    /// Deletes one recording and everything filed under it.
    ///
    /// The row cascades to the transcript, the notes, the annotations and the
    /// highlights, and the FTS indexes follow through their own triggers. What
    /// the database cannot do is remove the audio, so the file name is read
    /// first and handed back for the caller to unlink — the repository does not
    /// touch the disk, and `TransientAudio` is the only thing that does.
    ///
    /// **A recording that is still running is refused.** The microphone is open
    /// and the writer holds the file; deleting the row underneath it would
    /// leave a recording writing into a lecture that no longer exists.
    @discardableResult
    func delete(recording recordingID: Int64) async throws -> String? {
        try await database.writer.write { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT state, filename FROM recording WHERE id = ?",
                arguments: [recordingID]
            )
            guard let row else { return nil }
            guard (row["state"] as String?) != RecordingState.recording.rawValue else { return nil }

            let filename = row["filename"] as String?
            try db.execute(sql: "DELETE FROM recording WHERE id = ?", arguments: [recordingID])
            return filename
        }
    }

    /// Settles recordings that a quit or a crash left mid-flight.
    ///
    /// A row in `recording`, `transcribing` or `summarizing` is a claim that
    /// something is happening to it — and at launch nothing is, because the
    /// process that was doing it is gone. The library drew such a row as
    /// "recording" in red for ever, which is a lie the user cannot act on and
    /// cannot clear.
    ///
    /// They are settled to `done` rather than deleted. Whatever was written
    /// before the process died is real and belongs to the user; deciding for
    /// them that a short lecture is worthless is not this function's call. The
    /// row can now be deleted from the table if they want it gone.
    ///
    /// **Only safe at launch**, before anything starts recording — which is
    /// the only place it is called. Run later it would settle a lecture that is
    /// genuinely in progress.
    @discardableResult
    func settleInterruptedRecordings() async throws -> Int {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE recording SET state = ? WHERE state <> ?",
                arguments: [RecordingState.done.rawValue, RecordingState.done.rawValue]
            )
            return db.changesCount
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
