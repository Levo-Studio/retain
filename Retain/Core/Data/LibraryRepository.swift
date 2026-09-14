import Foundation
import GRDB

/// One course in the sidebar, with the two numbers drawn beside it.
///
/// They come out of the same grouped query as the course itself: asking for the
/// courses and then counting each one's recordings is one statement per course,
/// and the sidebar has a row per course.
nonisolated struct CourseListing: Identifiable, Hashable, Sendable {

    var course: Course
    /// Drawn at the right of the sidebar row, and in the course header.
    var recordingCount: Int
    /// Seconds over every recording in the course — "13 h 24 min" in the
    /// header.
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

    // MARK: - Courses

    /// The courses of one term, in the order they were created, each with the
    /// numbers the sidebar draws.
    func courses(in termID: Int64) async throws -> [CourseListing] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT course.*,
                       COUNT(recording.id) AS recordingCount,
                       COALESCE(SUM(recording.duration), 0) AS totalDuration
                FROM course
                LEFT JOIN recording ON recording.courseID = course.id
                WHERE course.termID = ?
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

    @discardableResult
    func save(_ course: Course) async throws -> Course {
        try await database.writer.write { db in
            var stored = course
            try stored.save(db)
            return stored
        }
    }

    // MARK: - Recordings

    /// Newest first, the way the table is drawn.
    ///
    /// By date **and** time: two recordings on one afternoon are ordinary, and
    /// sorting by the day alone would put them in whichever order the rows
    /// happened to be written.
    func recordings(in courseID: Int64) async throws -> [Recording] {
        try await database.writer.read { db in
            try Recording
                .filter(Recording.Columns.courseID == courseID)
                .order(Recording.Columns.startedAt.desc, Recording.Columns.id.desc)
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
    @discardableResult
    func startRecording(
        in courseID: Int64,
        at startedAt: Date = .now,
        filename: String? = nil
    ) async throws -> Recording {
        try await database.writer.write { db in
            var recording = Recording(
                courseID: courseID,
                startedAt: startedAt,
                state: .recording,
                filename: filename
            )
            try recording.insert(db)
            return recording
        }
    }
}
