import Foundation
import GRDB
import Testing

@testable import Retain

/// The picker board 02 does not draw. A recording belongs to exactly one
/// course, so what the picker answers decides whether a recording can start at
/// all.
@MainActor
@Suite("Course picker")
struct CourseSelectionTests {

    @Test("The courses are the current term's, and the first is picked")
    func picksTheFirstCourseOfTheCurrentTerm() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, isCurrent: true)
        try await StoreFixture.course(in: database, term: term, name: "Computer science")
        try await StoreFixture.course(in: database, term: term, name: "Mathematics")

        let selection = CourseSelection(library: LibraryRepository(database))
        await selection.reload()

        #expect(selection.courses.map(\.name) == ["Computer science", "Mathematics"])
        #expect(selection.selected?.name == "Computer science")
        #expect(selection.canRecord)
    }

    @Test("Another term's courses are not offered")
    func otherTermsAreNotOffered() async throws {
        let database = try StoreFixture.database()
        let current = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let past = try await StoreFixture.term(in: database, title: "Third year, summer")
        try await StoreFixture.course(in: database, term: current, name: "Computer science")
        try await StoreFixture.course(in: database, term: past, name: "Latin")

        let selection = CourseSelection(library: LibraryRepository(database))
        await selection.reload()

        #expect(selection.courses.map(\.name) == ["Computer science"])
    }

    @Test("A term with no courses in it cannot be recorded into")
    func aTermWithoutCourses() async throws {
        let database = try StoreFixture.database()
        try await StoreFixture.term(in: database, isCurrent: true)

        let selection = CourseSelection(library: LibraryRepository(database))
        await selection.reload()

        // Not an error and not an empty field left to look broken: the ready
        // state says "No course" and the Record button is unavailable, because
        // there is nothing for a recording to belong to.
        #expect(selection.courses.isEmpty)
        #expect(selection.selected == nil)
        #expect(!selection.canRecord)
        #expect(selection.hasLoaded)
    }

    @Test("No term at all is the same answer")
    func noTermAtAll() async throws {
        let database = try StoreFixture.database()

        let selection = CourseSelection(library: LibraryRepository(database))
        await selection.reload()

        #expect(selection.term == nil)
        #expect(!selection.canRecord)
    }

    @Test("A session with no database behind it still answers")
    func withoutAStore() async {
        // The app carries `nil` here when the database will not open, and the
        // popover has to draw something rather than crash.
        let selection = CourseSelection()
        await selection.reload()
        #expect(!selection.canRecord)
        #expect(selection.hasLoaded)
    }

    @Test("Picking a course keeps it")
    func picking() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, isCurrent: true)
        try await StoreFixture.course(in: database, term: term, name: "Computer science")
        let mathematics = try await StoreFixture.course(in: database, term: term, name: "Mathematics")

        let selection = CourseSelection(library: LibraryRepository(database))
        await selection.reload()
        selection.select(mathematics)
        #expect(selection.selected?.id == mathematics.id)

        // And survives a reload, because the popover re-reads every time it
        // opens and a choice that is forgotten on every open is not a choice.
        await selection.reload()
        #expect(selection.selected?.id == mathematics.id)
    }

    @Test("A course of another term cannot be picked")
    func pickingSomethingElse() async throws {
        let database = try StoreFixture.database()
        let current = try await StoreFixture.term(in: database, isCurrent: true)
        let past = try await StoreFixture.term(in: database, title: "Third year, summer")
        try await StoreFixture.course(in: database, term: current, name: "Computer science")
        let latin = try await StoreFixture.course(in: database, term: past, name: "Latin")

        let selection = CourseSelection(library: LibraryRepository(database))
        await selection.reload()
        selection.select(latin)

        #expect(selection.selected?.name == "Computer science")
    }

    @Test("A course that has gone falls back to the first one left")
    func aDeletedCourse() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, isCurrent: true)
        let first = try await StoreFixture.course(in: database, term: term, name: "Computer science")

        let selection = CourseSelection(library: LibraryRepository(database))
        await selection.reload()
        #expect(selection.selected?.id == first.id)

        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM course WHERE id = ?", arguments: [first.id])
        }
        try await StoreFixture.course(in: database, term: term, name: "Mathematics")
        await selection.reload()

        #expect(selection.selected?.name == "Mathematics")
    }
}

// MARK: - What the lecture does with it

@MainActor
@Suite("Lecture session")
struct LectureSessionTests {

    @Test("Nothing is marked while nothing is recording")
    func markersNeedALecture() {
        let session = LectureSession()
        session.addMarker("this is in the exam")
        #expect(session.markers.isEmpty)
    }

    @Test("A lecture that has not started belongs to no course and no term")
    func noCourseBeforeALecture() {
        let session = LectureSession()
        #expect(session.course == nil)
        #expect(session.term == nil)
        #expect(session.recordingID == nil)
        #expect(!session.isPaused)
    }

    /// A recording carries the term it was made in, and a term that was never
    /// written has no id to carry. The answer is refusal with something to
    /// read, not a row filed under a half-year that does not exist — and it is
    /// decided before the microphone or a gigabyte of weights is touched.
    @Test("A lecture will not start into a term that was never saved")
    func aLectureNeedsARealTerm() async {
        let session = LectureSession()
        await session.start(
            in: Course(id: 1, name: "Informatik", color: .accent),
            during: Term(title: "Third year, winter")
        )

        guard case .failed(let message) = session.phase else {
            Issue.record("A lecture started without a term to file it under")
            return
        }
        #expect(!message.isEmpty)
        #expect(session.recordingID == nil)
        #expect(session.recorder.state == .idle)
    }

    @Test("Pausing and resuming do nothing outside a lecture")
    func pausingOutsideALecture() {
        let session = LectureSession()
        session.pause()
        session.resume()
        #expect(session.phase == .idle)
        #expect(session.recorder.state == .idle)
    }

    @Test("Changing the course of a lecture that has none does nothing")
    func changingCourseWithoutALecture() {
        let session = LectureSession()
        session.changeCourse(to: Course(id: 1, name: "Mathematics", color: .blue))
        // No row to move, so the change is only the label — which is what the
        // meta strip then draws.
        #expect(session.course?.name == "Mathematics")
    }
}
