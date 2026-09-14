import Foundation
import GRDB
import Testing

@testable import Retain

@Suite("Library store")
struct LibraryStoreTests {

    // MARK: - Terms

    @Test("A term comes back the way it went in")
    func termRoundTrips() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)

        let saved = try await repository.save(
            Term(
                title: "Third year, winter",
                startsOn: StoreFixture.instant(2025, 10),
                endsOn: StoreFixture.instant(2026, 3)
            )
        )

        let id = try #require(saved.id)
        let read = try #require(try await repository.term(id))
        #expect(read.title == "Third year, winter")
        #expect(read.startsOn == StoreFixture.instant(2025, 10))
        #expect(read.endsOn == StoreFixture.instant(2026, 3))
        #expect(read.isCurrent == false)
    }

    /// A term is a half-year or a semester, and it is the term that says which
    /// — not a setting, so switching later leaves the terms already recorded
    /// labelled the way they were lived.
    @Test("Both kinds of term survive the round trip", arguments: TermKind.allCases)
    func termKindsRoundTrip(_ kind: TermKind) async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, kind: kind)
        let id = try #require(term.id)

        #expect(try await LibraryRepository(database).term(id)?.kind == kind)
    }

    @Test("A term defaults to a half-year, which is what the design draws")
    func termDefaultsToHalfYear() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database)

        #expect(term.kind == .halfYear)
    }

    @Test("Two terms of different kinds live side by side")
    func kindsAreNotGlobal() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)

        try await StoreFixture.term(in: database, title: "Third year, winter", kind: .halfYear)
        try await StoreFixture.term(
            in: database,
            title: "First semester",
            kind: .semester,
            startsOn: StoreFixture.instant(2026, 4),
            endsOn: StoreFixture.instant(2026, 9)
        )

        #expect(try await repository.terms().map(\.kind) == [.semester, .halfYear])
    }

    @Test("Terms come back newest first, which is how the picker opens")
    func termsAreNewestFirst() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)

        try await StoreFixture.term(
            in: database,
            title: "Second year, summer",
            startsOn: StoreFixture.instant(2025, 4),
            endsOn: StoreFixture.instant(2025, 9)
        )
        try await StoreFixture.term(in: database, title: "Third year, winter")

        #expect(try await repository.terms().map(\.title) == ["Third year, winter", "Second year, summer"])
    }

    @Test("Exactly one term is the current one")
    func onlyOneTermIsCurrent() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)

        let first = try await StoreFixture.term(in: database, title: "Second year, summer", isCurrent: true)
        let second = try await StoreFixture.term(in: database, title: "Third year, winter")

        try await repository.makeCurrent(try #require(second.id))

        #expect(try await repository.currentTerm()?.id == second.id)
        #expect(try await repository.term(try #require(first.id))?.isCurrent == false)
    }

    /// The guarantee is in the schema, not in the repository, so a second way
    /// of writing a row cannot get around it.
    @Test("A second current term is refused by the database itself")
    func aSecondCurrentTermIsRefused() async throws {
        let database = try StoreFixture.database()
        try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)

        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                var intruder = Term(
                    title: "Fourth year, summer",
                    startsOn: StoreFixture.instant(2026, 4),
                    endsOn: StoreFixture.instant(2026, 9),
                    isCurrent: true
                )
                try intruder.insert(db)
            }
        }
    }

    @Test("Before a term has been named there is no current one")
    func noCurrentTermAtFirst() async throws {
        let database = try StoreFixture.database()
        #expect(try await LibraryRepository(database).currentTerm() == nil)
    }

    // MARK: - Courses

    @Test("A course belongs to one term and shows up only under it")
    func coursesAreScopedToTheirTerm() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)

        let winter = try await StoreFixture.term(in: database, title: "Third year, winter")
        let summer = try await StoreFixture.term(
            in: database,
            title: "Third year, summer",
            startsOn: StoreFixture.instant(2026, 4),
            endsOn: StoreFixture.instant(2026, 9)
        )

        try await StoreFixture.course(in: database, term: winter, name: "Computer science")
        try await StoreFixture.course(in: database, term: winter, name: "Mathematics", color: .blue)
        try await StoreFixture.course(in: database, term: summer, name: "Biology", color: .purple)

        let winterCourses = try await repository.courses(in: try #require(winter.id))
        #expect(winterCourses.map(\.course.name) == ["Computer science", "Mathematics"])
        #expect(winterCourses.map(\.course.color) == [.accent, .blue])

        let summerCourses = try await repository.courses(in: try #require(summer.id))
        #expect(summerCourses.map(\.course.name) == ["Biology"])
    }

    @Test("A course carries the count and the total the sidebar draws")
    func courseListingCountsRecordings() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)
        let term = try await StoreFixture.term(in: database)
        let course = try await StoreFixture.course(in: database, term: term)
        let courseID = try #require(course.id)

        for minutes in [92.0, 88.0, 90.0] {
            var recording = try await repository.startRecording(in: courseID)
            recording.duration = minutes * 60
            try await repository.save(recording)
        }

        let termID = try #require(term.id)
        let listing = try #require(try await repository.courses(in: termID).first)
        #expect(listing.recordingCount == 3)
        #expect(listing.totalDuration == 270 * 60)
    }

    @Test("A course with no recordings counts zero rather than disappearing")
    func emptyCourseStillAppears() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database)
        try await StoreFixture.course(in: database, term: term, name: "Physics", color: .amber)

        let termID = try #require(term.id)
        let listing = try #require(try await LibraryRepository(database).courses(in: termID).first)
        #expect(listing.recordingCount == 0)
        #expect(listing.totalDuration == 0)
    }

    @Test("Every one of the four colours survives the round trip", arguments: CourseColor.allCases)
    func colorsRoundTrip(_ color: CourseColor) async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database)
        let course = try await StoreFixture.course(in: database, term: term, color: color)

        #expect(try await LibraryRepository(database).course(try #require(course.id))?.color == color)
    }

    // MARK: - Recordings

    @Test("A recording starts as a recording with no topic")
    func aNewRecordingHasNoTopic() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)

        #expect(library.recording.state == .recording)
        #expect(library.recording.topic == nil)
        #expect(library.recording.duration == 0)
        #expect(library.recording.filename == nil)
    }

    /// What a recording is identified by. Nothing truncates it to the day, and
    /// nothing numbers it.
    @Test("A recording keeps the time of day it started at")
    func aRecordingKeepsItsTimeOfDay() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)
        let term = try await StoreFixture.term(in: database)
        let course = try await StoreFixture.course(in: database, term: term)

        let started = StoreFixture.instant(2026, 2, 7, 14, 45)
        let recording = try await repository.startRecording(in: try #require(course.id), at: started)

        #expect(try await repository.recording(try #require(recording.id))?.startedAt == started)
    }

    @Test("Two recordings on one afternoon are ordinary, and stay apart")
    func twoRecordingsInOneDay() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)
        let term = try await StoreFixture.term(in: database)
        let course = try await StoreFixture.course(in: database, term: term)
        let courseID = try #require(course.id)

        let morning = StoreFixture.instant(2026, 2, 7, 9, 0)
        let afternoon = StoreFixture.instant(2026, 2, 7, 14, 30)
        try await repository.startRecording(in: courseID, at: morning)
        try await repository.startRecording(in: courseID, at: afternoon)

        let recordings = try await repository.recordings(in: courseID)
        #expect(recordings.count == 2)
        #expect(recordings.map(\.startedAt) == [afternoon, morning])
    }

    @Test("What the pass after the recording writes back stays written")
    func aRecordingCanBeFinished() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)
        let library = try await StoreFixture.library(in: database)

        var recording = library.recording
        recording.state = .done
        recording.topic = "Seitenersetzung und Working Set"
        recording.duration = 92 * 60
        recording.filename = "2026-02-07-101500-AB12CD.caf"
        try await repository.save(recording)

        let recordingID = try #require(recording.id)
        let read = try #require(try await repository.recording(recordingID))
        #expect(read.state == .done)
        #expect(read.topic == "Seitenersetzung und Working Set")
        #expect(read.duration == 92 * 60)
        // The file name, never a path: the folder comes from `RecordingStore`.
        #expect(read.filename?.contains("/") == false)
    }

    @Test("Every state survives the round trip", arguments: RecordingState.allCases)
    func recordingStatesRoundTrip(_ state: RecordingState) async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)
        var recording = try await StoreFixture.library(in: database).recording
        recording.state = state
        try await repository.save(recording)

        #expect(try await repository.recording(try #require(recording.id))?.state == state)
    }

    @Test("The table is drawn newest first")
    func recordingsAreNewestFirst() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)
        let term = try await StoreFixture.term(in: database)
        let course = try await StoreFixture.course(in: database, term: term)
        let courseID = try #require(course.id)

        for month in 1...3 {
            try await repository.startRecording(in: courseID, at: StoreFixture.instant(2026, month))
        }

        let dates = try await repository.recordings(in: courseID).map(\.startedAt)
        #expect(dates == [
            StoreFixture.instant(2026, 3),
            StoreFixture.instant(2026, 2),
            StoreFixture.instant(2026, 1),
        ])
    }

    /// What makes removing a course a single statement rather than a walk down
    /// the tree that forgets a table.
    @Test("Deleting a course takes its recordings and everything in them")
    func deletingACourseCascades() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let courseID = try #require(library.course.id)

        let transcript = TranscriptRepository(database)
        let notes = NoteRepository(database)
        try await transcript.append(StoreFixture.line("Paging", at: 5), to: recordingID)
        try await transcript.annotate(at: 5, note: "exam relevant", in: recordingID)
        let block = try await notes.append(
            StoreFixture.noteBlock("## Paging\n\nPages, frames, and the page table."),
            to: recordingID
        )
        try await notes.highlight(block, from: 0, to: 9)

        try await database.writer.write { db in
            _ = try Course.deleteOne(db, key: courseID)
        }

        #expect(try await LibraryRepository(database).recording(recordingID) == nil)
        #expect(try await transcript.lines(for: recordingID).isEmpty)
        #expect(try await transcript.annotations(for: recordingID).isEmpty)
        #expect(try await notes.blocks(for: recordingID).isEmpty)
        #expect(try await notes.highlights(for: recordingID).isEmpty)
    }
}
