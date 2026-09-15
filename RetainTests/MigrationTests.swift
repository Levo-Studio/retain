import Foundation
import GRDB
import Testing

@testable import Retain

@Suite("Migrations")
struct MigrationTests {

    // MARK: - Applying

    @Test("An empty database ends up with every migration applied, in order")
    func allMigrationsApplyToAnEmptyDatabase() throws {
        let database = try StoreFixture.database()

        #expect(try database.appliedMigrations() == RetainMigration.allCases.map(\.rawValue))
    }

    @Test("Each migration brings its own tables and nothing else")
    func eachMigrationBringsItsOwnTables() throws {
        let library = try StoreFixture.database(upTo: .library)
        #expect(try library.tableNames().isSuperset(of: ["term", "course", "courseTerm", "recording"]))
        #expect(try library.tableNames().isDisjoint(with: [
            "transcriptLine", "annotation", "noteBlock", "highlight",
        ]))

        let content = try StoreFixture.database(upTo: .recordingContent)
        #expect(try content.tableNames().isSuperset(of: [
            "transcriptLine", "annotation", "noteBlock", "highlight",
        ]))
        #expect(try content.tableNames().isDisjoint(with: [
            "transcriptLineSearch", "noteBlockSearch", "annotationSearch",
        ]))

        let search = try StoreFixture.database(upTo: .search)
        #expect(try search.tableNames().isSuperset(of: [
            "transcriptLineSearch", "noteBlockSearch", "annotationSearch",
        ]))
    }

    @Test("Running the migrator again on a migrated database changes nothing")
    func migratingTwiceIsHarmless() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let transcript = TranscriptRepository(database)
        try await transcript.append(StoreFixture.line("Paging", at: 10), to: recordingID)

        let before = try database.tableNames()
        try database.migrate()

        #expect(try database.tableNames() == before)
        #expect(try database.appliedMigrations() == RetainMigration.allCases.map(\.rawValue))
        #expect(try await transcript.lines(for: recordingID).count == 1)
    }

    /// The case that catches a search index built with `CREATE VIRTUAL TABLE`
    /// and nothing else: on an empty database the triggers are enough, because
    /// every row arrives after them. On a database that already holds a term of
    /// recordings, a migration that only installs triggers leaves every one of
    /// them unfindable.
    @Test("The search migration indexes the recordings that are already there")
    func searchMigrationIndexesExistingRows() async throws {
        let database = try StoreFixture.database(upTo: .recordingContent)
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)

        try await TranscriptRepository(database).append(
            StoreFixture.line("Der Second-Chance-Algorithmus prüft das Referenzbit.", at: 61),
            to: recordingID
        )
        try await TranscriptRepository(database).annotate(
            at: 61,
            note: "Übungsblatt 5",
            in: recordingID
        )
        try await NoteRepository(database).append(
            StoreFixture.noteBlock("## Seitenersetzung\n\nFIFO leidet unter der Bélády-Anomalie."),
            to: recordingID
        )

        try RetainMigrations.migrator.migrate(database.writer)

        let search = SearchRepository(database)
        #expect(try await search.search("Referenzbit", in: termID).first?.source == .transcript)
        #expect(try await search.search("FIFO", in: termID).first?.source == .note)
        #expect(try await search.search("Übungsblatt", in: termID).first?.source == .annotation)
    }

    @Test("Content written before the search migration is still there after it")
    func contentSurvivesTheSearchMigration() async throws {
        let database = try StoreFixture.database(upTo: .recordingContent)
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let transcript = TranscriptRepository(database)

        try await transcript.replaceLines(
            (0..<50).map { StoreFixture.line("Line \($0)", at: Double($0) * 5) },
            for: recordingID
        )

        try RetainMigrations.migrator.migrate(database.writer)

        let lines = try await transcript.lines(for: recordingID)
        #expect(lines.count == 50)
        #expect(lines.first?.text == "Line 0")
        #expect(lines.last?.text == "Line 49")
    }

    // MARK: - Rolling back

    @Test("The search migration rolls back and takes only the index with it")
    func searchRollsBack() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)
        let transcript = TranscriptRepository(database)

        try await transcript.append(StoreFixture.line("Working Set und Thrashing", at: 120), to: recordingID)
        #expect(try await SearchRepository(database).search("Thrashing", in: termID).count == 1)

        try database.rollBack(.search)

        #expect(try database.tableNames().isDisjoint(with: [
            "transcriptLineSearch", "noteBlockSearch", "annotationSearch",
        ]))
        // Everything except the one that was rolled back. `v4` is in the list
        // because it ran — on a database this migrator built it finds the
        // current shape and does nothing, which is the point of it.
        #expect(try database.appliedMigrations() == [
            RetainMigration.library.rawValue,
            RetainMigration.recordingContent.rawValue,
            RetainMigration.coursesAcrossTerms.rawValue,
            RetainMigration.mergedRecordings.rawValue,
        ])

        // The transcript is untouched, which is the whole point: the index was
        // derived from it and nothing else.
        let lines = try await transcript.lines(for: recordingID)
        #expect(lines.count == 1)
        #expect(lines.first?.text == "Working Set und Thrashing")
    }

    @Test("A recording still takes writes while the search index is rolled back")
    func writesWorkWithoutTheIndex() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)

        try database.rollBack(.search)

        // A leftover synchronisation trigger would fail these writes: it would
        // be writing into a table that is no longer there.
        let transcript = TranscriptRepository(database)
        try await transcript.append(StoreFixture.line("Clock als Ringpuffer", at: 300), to: recordingID)
        try await transcript.annotate(at: 300, note: "klausurrelevant", in: recordingID)
        try await NoteRepository(database).append(
            StoreFixture.noteBlock("## Clock\n\nSecond Chance als Ring gelesen."),
            to: recordingID
        )

        #expect(try await transcript.lines(for: recordingID).count == 1)
        #expect(try await transcript.annotations(for: recordingID).count == 1)
        #expect(try await NoteRepository(database).blocks(for: recordingID).count == 1)
    }

    @Test("Migrating again after the rollback rebuilds the index from the rows")
    func searchComesBackAfterTheRollback() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)

        try await TranscriptRepository(database).append(
            StoreFixture.line("Working Set und Thrashing", at: 120),
            to: recordingID
        )

        try database.rollBack(.search)
        try database.migrate()

        #expect(try database.appliedMigrations() == RetainMigration.allCases.map(\.rawValue))
        #expect(try await SearchRepository(database).search("Thrashing", in: termID).count == 1)
    }

    /// The two that hold user content have no rollback on purpose. Undoing
    /// either one means dropping the tables every recording lives in, and a
    /// method that does that quietly is a method something will eventually call
    /// by accident.
    @Test("The two migrations that hold recordings refuse to roll back", arguments: [
        RetainMigration.library,
        RetainMigration.recordingContent,
    ])
    func contentMigrationsRefuseToRollBack(_ migration: RetainMigration) async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        try await TranscriptRepository(database).append(StoreFixture.line("Paging", at: 3), to: recordingID)

        #expect(throws: RetainDatabaseError.migrationHasNoRollback(migration.rawValue)) {
            try database.rollBack(migration)
        }

        // And it refused without taking anything with it.
        #expect(try database.tableNames().isSuperset(of: [
            "term", "course", "courseTerm", "recording", "transcriptLine",
        ]))
        #expect(try await TranscriptRepository(database).lines(for: recordingID).count == 1)
    }
}
