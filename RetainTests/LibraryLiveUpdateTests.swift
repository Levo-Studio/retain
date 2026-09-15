import Foundation
import GRDB
import Testing

@testable import Retain

/// A window that is already open sees what another window just wrote.
///
/// **This suite exists because Retain had to be quit.** Every window read its
/// lists once and kept them: a course created in Settings never appeared in the
/// library, a deleted term stayed in the picker, and the only way to see either
/// was to quit the app and open it again. Each window was right about what it
/// had read — nothing told it that it was no longer true.
@Suite("Live updates across windows")
struct LibraryLiveUpdateTests {

    // MARK: - The signal

    @Test("Writing a course wakes the stream")
    func aWriteWakesTheStream() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)

        var iterator = LibraryChanges.stream(in: database).makeAsyncIterator()

        // The first element arrives without anything having changed, which is
        // what lets a window use this as its load as well as its subscription.
        _ = try await iterator.next()

        try await StoreFixture.course(in: database, term: term, name: "Informatik")

        let woken = try await iterator.next()
        #expect(woken != nil)
    }

    // MARK: - What the window does with it

    @Test("A course added elsewhere appears without losing the selected course")
    func addingACourseKeepsTheSelection() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let informatik = try await StoreFixture.course(in: database, term: term, name: "Informatik")

        let model = await LibraryModel(database: database)
        await model.refresh()
        #expect(await model.selectedCourse?.id == informatik.id)

        // Another window creates a course.
        try await StoreFixture.course(in: database, term: term, name: "Chemie")
        await model.refresh()

        #expect(await model.courses.count == 2)
        // And the reader is still on the course they were reading. A refresh
        // that jumped to the first course would move the table out from under
        // somebody who was not doing anything.
        #expect(await model.selectedCourse?.id == informatik.id)
    }

    @Test("A deleted course drops the selection onto one that still exists")
    func deletingTheSelectedCourseFallsBack() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let informatik = try await StoreFixture.course(in: database, term: term, name: "Informatik")
        let chemie = try await StoreFixture.course(in: database, term: term, name: "Chemie")

        let model = await LibraryModel(database: database)
        await model.refresh()
        await model.select(course: try #require(await model.courses.first { $0.id == chemie.id }))

        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM course WHERE id = ?", arguments: [chemie.id])
        }
        await model.refresh()

        #expect(await model.courses.map(\.id) == [informatik.id])
        #expect(await model.selectedCourse?.id == informatik.id)
    }

    @Test("Deleting the term the window is on moves it to one that is left")
    func deletingTheSelectedTermFallsBack() async throws {
        let database = try StoreFixture.database()
        let winter = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let summer = try await StoreFixture.term(
            in: database,
            title: "Third year, summer",
            startsOn: StoreFixture.instant(2026, 4),
            endsOn: StoreFixture.instant(2026, 9)
        )
        try await StoreFixture.course(in: database, term: summer, name: "Chemie")

        let model = await LibraryModel(database: database)
        await model.refresh()
        #expect(await model.selectedTerm?.id == winter.id)

        try await LibraryRepository(database).delete(term: try #require(winter.id))
        await model.refresh()

        #expect(await model.selectedTerm?.id == summer.id)
        #expect(await model.courses.map(\.course.name) == ["Chemie"])
    }

    @Test("Deleting the last term leaves the window showing nothing")
    func deletingEveryTermClearsTheWindow() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        try await StoreFixture.course(in: database, term: term, name: "Informatik")

        let model = await LibraryModel(database: database)
        await model.refresh()

        try await LibraryRepository(database).delete(term: try #require(term.id))
        await model.refresh()

        // The sidebar used to keep the deleted term's courses, and clicking one
        // asked the database for recordings in a term that was gone.
        #expect(await model.terms.isEmpty)
        #expect(await model.selectedTerm == nil)
        #expect(await model.courses.isEmpty)
        #expect(await model.recordings.isEmpty)
    }

    // MARK: - Recording from the library

    @Test("The Record button is unavailable until there is a course and a shell")
    func recordingNeedsACourseAndAShell() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)

        let model = await LibraryModel(database: database)
        await model.refresh()

        // No course, no shell.
        #expect(await model.isRecordable == false)

        try await StoreFixture.course(in: database, term: term, name: "Informatik")
        await model.refresh()
        // A course, but still nothing that can start a recording.
        #expect(await model.isRecordable == false)

        await MainActor.run {
            model.onRecord = { _, _ in }
            model.canRecord = { true }
        }
        #expect(await model.isRecordable)
    }

    @Test("Pressing Record names the course the window is on")
    func recordingNamesTheSelectedCourse() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        try await StoreFixture.course(in: database, term: term, name: "Informatik")
        let chemie = try await StoreFixture.course(in: database, term: term, name: "Chemie")

        let model = await LibraryModel(database: database)
        await model.refresh()
        await model.select(course: try #require(await model.courses.first { $0.id == chemie.id }))

        let asked = Asked()
        await MainActor.run {
            model.canRecord = { true }
            model.onRecord = { course, term in asked.record(course: course, term: term) }
        }
        await model.record()

        // The course the reader is looking at, not the first one and not
        // whatever the menu bar's own picker happens to hold.
        #expect(asked.course?.id == chemie.id)
        #expect(asked.term?.id == term.id)
    }

    /// What the window asked for, kept outside the model.
    private nonisolated final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var pair: (Course, Term)?

        func record(course: Course, term: Term) {
            lock.lock()
            pair = (course, term)
            lock.unlock()
        }

        var course: Course? {
            lock.lock(); defer { lock.unlock() }
            return pair?.0
        }

        var term: Term? {
            lock.lock(); defer { lock.unlock() }
            return pair?.1
        }
    }
}
