import Foundation
import GRDB
import Testing

@testable import Retain

/// A database created by the **first** shipped `v1.library`, before a course
/// could run in more than one term.
///
/// This exists because `v1.library` was edited in place after it had shipped.
/// The migrator only ever compares identifiers, so every install that already
/// had `v1.library` recorded kept the old tables for good: no `courseTerm`, no
/// `recording.termID`, a `course.termID` instead, and a term whose period was
/// required. Every query the library makes hit one of those and threw behind a
/// `try?`, so the app looked as though its buttons did nothing.
///
/// The DDL below is copied verbatim out of such a database. It must not be
/// "tidied" to match the current schema — the point of it is to be the shape
/// that is out in the world.
@Suite("Migrating a database from before courses ran across terms")
struct LegacySchemaMigrationTests {

    /// Builds the old shape and records the three migrations that had shipped,
    /// exactly as the migrator would have left it.
    private func legacyDatabase() throws -> RetainDatabase {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE "term" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL,
                    "kind" TEXT NOT NULL, "startsOn" DATETIME NOT NULL, "endsOn" DATETIME NOT NULL,
                    "isCurrent" BOOLEAN NOT NULL DEFAULT 0);
                CREATE UNIQUE INDEX "termOnIsCurrent" ON "term"("isCurrent") WHERE "isCurrent";

                CREATE TABLE "course" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "termID" INTEGER NOT NULL REFERENCES "term"("id") ON DELETE CASCADE,
                    "name" TEXT NOT NULL, "color" INTEGER NOT NULL);
                CREATE INDEX "courseOnTermID" ON "course"("termID");

                CREATE TABLE "recording" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "courseID" INTEGER NOT NULL REFERENCES "course"("id") ON DELETE CASCADE,
                    "startedAt" DATETIME NOT NULL, "duration" DOUBLE NOT NULL DEFAULT 0,
                    "state" TEXT NOT NULL, "topic" TEXT, "filename" TEXT);
                CREATE INDEX "recordingOnCourseIDAndStartedAt" ON "recording"("courseID", "startedAt");
                """)
        }

        // v2 and v3 were never touched, so they are registered normally and
        // run on top of the hand-built v1.
        var early = DatabaseMigrator()
        early.registerMigration(RetainMigration.library.rawValue) { _ in }
        try early.migrate(queue, upTo: RetainMigration.library.rawValue)

        let database = RetainDatabase(writer: queue)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE "transcriptLine" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "recordingID" INTEGER NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE,
                    "uuid" BLOB NOT NULL, "startTime" DOUBLE NOT NULL, "endTime" DOUBLE NOT NULL,
                    "text" TEXT NOT NULL, "speaker" TEXT NOT NULL,
                    "isProvisional" BOOLEAN NOT NULL DEFAULT 0);
                CREATE INDEX "transcriptLineOnRecordingIDAndStartTime"
                    ON "transcriptLine"("recordingID", "startTime");

                CREATE TABLE "annotation" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "recordingID" INTEGER NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE,
                    "time" DOUBLE NOT NULL, "note" TEXT);
                CREATE INDEX "annotationOnRecordingIDAndTime" ON "annotation"("recordingID", "time");

                CREATE TABLE "noteBlock" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "recordingID" INTEGER NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE,
                    "position" INTEGER NOT NULL, "startTime" DOUBLE NOT NULL,
                    "endTime" DOUBLE NOT NULL, "markdown" TEXT NOT NULL);
                CREATE INDEX "noteBlockOnRecordingIDAndPosition" ON "noteBlock"("recordingID", "position");

                CREATE TABLE "highlight" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "recordingID" INTEGER NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE,
                    "noteBlockID" INTEGER NOT NULL REFERENCES "noteBlock"("id") ON DELETE CASCADE,
                    "startOffset" INTEGER NOT NULL, "endOffset" INTEGER NOT NULL,
                    "text" TEXT NOT NULL, "createdAt" DATETIME NOT NULL);
                CREATE INDEX "highlightOnNoteBlockIDAndStartOffset"
                    ON "highlight"("noteBlockID", "startOffset");
                CREATE INDEX "highlightOnRecordingID" ON "highlight"("recordingID");

                INSERT INTO grdb_migrations (identifier) VALUES ('v2.recording-content');
                """)
        }

        return database
    }

    /// A term, two courses in it, a recording in each, and a transcript line
    /// under one of them — enough that losing any of it would show.
    private func fillLegacy(_ database: RetainDatabase) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO term (id, title, kind, startsOn, endsOn, isCurrent)
                VALUES (1, 'Third year, winter', 'halfYear', '2025-10-01 12:00:00', '2026-03-01 12:00:00', 1);

                INSERT INTO course (id, termID, name, color) VALUES (1, 1, 'Informatik', 0), (2, 1, 'Chemie', 1);

                INSERT INTO recording (id, courseID, startedAt, duration, state, topic, filename)
                VALUES (1, 1, '2025-11-03 10:00:00', 2700, 'done', 'Sortieren', NULL),
                       (2, 2, '2025-11-04 10:00:00', 1800, 'done', NULL, NULL);

                INSERT INTO transcriptLine (id, recordingID, uuid, startTime, endTime, text, speaker, isProvisional)
                VALUES (1, 1, x'00112233445566778899aabbccddeeff', 0, 4, 'Guten Morgen', 'lecturer', 0);
                """)
        }
    }

    // MARK: -

    @Test("An old database reaches the current schema")
    func theOldShapeIsRepaired() throws {
        let database = try legacyDatabase()
        try fillLegacy(database)

        try RetainMigrations.migrator.migrate(database.writer)

        let shape = try database.writer.read { db in
            (
                hasCourseTerm: try db.tableExists("courseTerm"),
                recordingColumns: try db.columns(in: "recording").map(\.name),
                courseColumns: try db.columns(in: "course").map(\.name)
            )
        }
        #expect(shape.hasCourseTerm)
        #expect(shape.recordingColumns.contains("termID"))
        #expect(!shape.courseColumns.contains("termID"))
    }

    @Test("Every course keeps the term it was in")
    func coursesKeepTheirTerm() throws {
        let database = try legacyDatabase()
        try fillLegacy(database)

        try RetainMigrations.migrator.migrate(database.writer)

        let pairs = try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT courseID, termID FROM courseTerm ORDER BY courseID")
        }
        #expect(pairs.count == 2)
        #expect(pairs.allSatisfy { $0["termID"] == Int64(1) })
    }

    @Test("Every recording keeps its course, and gains that course's term")
    func recordingsGainTheirTerm() throws {
        let database = try legacyDatabase()
        try fillLegacy(database)

        try RetainMigrations.migrator.migrate(database.writer)

        let rows = try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT id, courseID, termID, topic FROM recording ORDER BY id")
        }
        #expect(rows.count == 2)
        #expect(rows.map { $0["courseID"] as Int64 } == [1, 2])
        #expect(rows.allSatisfy { $0["termID"] == Int64(1) })
        // And the columns that were only ever copied across are still there.
        #expect(rows.first?["topic"] == "Sortieren")
    }

    @Test("Recreating the recording table does not take the transcript with it")
    func transcriptsSurviveTheRebuild() throws {
        let database = try legacyDatabase()
        try fillLegacy(database)

        try RetainMigrations.migrator.migrate(database.writer)

        // The rebuild drops and recreates `recording`. With foreign keys on
        // that is a cascading delete through every transcript line, note and
        // highlight in the database — which is why the migrator's deferred
        // foreign key checks are load-bearing here and not a default nobody
        // thought about.
        let lines = try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT recordingID, text FROM transcriptLine")
        }
        #expect(lines.count == 1)
        #expect(lines.first?["text"] == "Guten Morgen")
    }

    @Test("The term's period becomes optional and keeps what it held")
    func theTermKeepsItsPeriod() throws {
        let database = try legacyDatabase()
        try fillLegacy(database)

        try RetainMigrations.migrator.migrate(database.writer)

        let term = try #require(try database.writer.read { try Term.fetchOne($0) })
        #expect(term.title == "Third year, winter")
        #expect(term.isCurrent)
        #expect(term.startsOn != nil)

        // And a term with no period is now writable, which is the change the
        // edited migration was making in the first place.
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO term (title, kind, startsOn, endsOn, isCurrent)
                VALUES ('Third year, summer', 'halfYear', NULL, NULL, 0)
                """)
        }
        #expect(try database.writer.read { try Term.fetchCount($0) } == 2)
    }

    @Test("The repaired database answers the queries that used to throw")
    func theLibraryWorksAfterwards() async throws {
        let database = try legacyDatabase()
        try fillLegacy(database)
        try RetainMigrations.migrator.migrate(database.writer)

        let repository = LibraryRepository(database)
        let term = try #require(try await repository.currentTerm())
        let termID = try #require(term.id)

        // Every one of these threw `no such table: courseTerm` or
        // `no such column: termID` on the old shape, behind a `try?`.
        // In the sidebar's own order, which is the order the courses were
        // created in — not alphabetical.
        let courses = try await repository.courses(in: termID)
        #expect(courses.map(\.course.name) == ["Informatik", "Chemie"])

        let impact = try await repository.deletionImpact(of: termID)
        #expect(impact.recordings == 2)
        #expect(impact.coursesLost == ["Chemie", "Informatik"])
    }

    @Test("A database built by the current migrations is left alone")
    func aFreshDatabaseIsUntouched() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        try await StoreFixture.course(in: database, term: term, name: "Informatik")

        // The repair is guarded on the old shape, so running the migrator again
        // over a current database must be a no-op rather than a rebuild.
        try RetainMigrations.migrator.migrate(database.writer)

        #expect(try await database.writer.read { try Course.fetchCount($0) } == 1)
        #expect(try await LibraryRepository(database).courses(in: try #require(term.id)).count == 1)
    }
}
