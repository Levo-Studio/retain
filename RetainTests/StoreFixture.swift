import Foundation
import GRDB

@testable import Retain

/// Builds the little library every store test needs.
///
/// Every database here is in memory and named after nothing, so two tests
/// running at the same time cannot see each other's rows and none of them can
/// reach the real `Retain.sqlite`.
nonisolated enum StoreFixture {

    static func database() throws -> RetainDatabase {
        try RetainDatabase.inMemory()
    }

    /// A database with the schema of one migration and not the ones after it.
    static func database(upTo migration: RetainMigration) throws -> RetainDatabase {
        let database = RetainDatabase(writer: try DatabaseQueue())
        try RetainMigrations.migrator.migrate(database.writer, upTo: migration.rawValue)
        return database
    }

    /// A fixed instant, in UTC.
    ///
    /// Fixed components rather than `Date.now`: a term that starts "now" makes
    /// an assertion depend on the machine's clock and time zone, and a date
    /// with a fraction of a second in it does not survive the round trip
    /// through SQLite's millisecond format unchanged.
    static func instant(
        _ year: Int,
        _ month: Int,
        _ day: Int = 1,
        _ hour: Int = 12,
        _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return .distantPast }
        calendar.timeZone = utc

        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components) ?? .distantPast
    }

    @discardableResult
    static func term(
        in database: RetainDatabase,
        title: String = "Third year, winter",
        kind: TermKind = .halfYear,
        startsOn: Date = instant(2025, 10),
        endsOn: Date = instant(2026, 3),
        isCurrent: Bool = false
    ) async throws -> Term {
        try await LibraryRepository(database).save(
            Term(
                title: title,
                kind: kind,
                startsOn: startsOn,
                endsOn: endsOn,
                isCurrent: isCurrent
            )
        )
    }

    @discardableResult
    static func course(
        in database: RetainDatabase,
        term: Term,
        name: String = "Computer science",
        color: CourseColor = .accent
    ) async throws -> Course {
        guard let termID = term.id else { throw StoreFixtureError.unsavedRow }
        return try await LibraryRepository(database).save(
            Course(termID: termID, name: name, color: color)
        )
    }

    @discardableResult
    static func recording(
        in database: RetainDatabase,
        course: Course,
        at startedAt: Date = instant(2026, 2, 7, 10, 15)
    ) async throws -> Recording {
        guard let courseID = course.id else { throw StoreFixtureError.unsavedRow }
        return try await LibraryRepository(database).startRecording(in: courseID, at: startedAt)
    }

    /// A term with one course and one recording in it, which is what most tests
    /// need before they can say anything.
    static func library(
        in database: RetainDatabase
    ) async throws -> (term: Term, course: Course, recording: Recording) {
        let term = try await term(in: database, isCurrent: true)
        let course = try await course(in: database, term: term)
        let recording = try await recording(in: database, course: course)
        return (term, course, recording)
    }

    /// The `recordingID` is a placeholder: every writing method on
    /// `NoteRepository` takes the recording as its own argument and overwrites
    /// it, so a block cannot be filed under the wrong recording by a typo here.
    static func noteBlock(
        _ markdown: String,
        position: Int = 0,
        startTime: TimeInterval = 0
    ) -> StoredNoteBlock {
        StoredNoteBlock(
            recordingID: 0,
            position: position,
            startTime: startTime,
            markdown: markdown
        )
    }

    static func line(
        _ text: String,
        at start: TimeInterval,
        to end: TimeInterval? = nil,
        speaker: SpeakerRole = .lecturer,
        isProvisional: Bool = false
    ) -> TranscriptLine {
        TranscriptLine(
            start: start,
            end: end ?? start + 4,
            text: text,
            speaker: speaker,
            isProvisional: isProvisional
        )
    }
}

nonisolated enum StoreFixtureError: Error {
    /// A fixture was handed a record that was never written, so it has no id.
    case unsavedRow
}

// MARK: -

nonisolated extension RetainDatabase {

    /// The tables and virtual tables in this database, for the migration tests.
    func tableNames() throws -> Set<String> {
        try writer.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
    }
}
