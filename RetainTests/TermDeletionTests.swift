import Foundation
import GRDB
import Testing

@testable import Retain

/// Deleting a term — the one action in Retain that destroys work.
///
/// Everything else can be undone by doing it again: a renamed course can be
/// renamed back, a course moved out of a term can be moved into it. A deleted
/// term takes recordings with it, and a recording is a lecture somebody sat
/// through once. So what is tested here is not only that the rows go, but that
/// the count shown to the reader beforehand is the truth, and that a course
/// which also runs somewhere else is not collateral.
@Suite("Deleting a term")
struct TermDeletionTests {

    /// Two half-years. `shared` runs in both, `winterOnly` in one. One
    /// recording in each term.
    private func year(
        in database: RetainDatabase
    ) async throws -> (winter: Term, summer: Term, shared: Course, winterOnly: Course) {
        let winter = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let summer = try await StoreFixture.term(
            in: database,
            title: "Third year, summer",
            startsOn: StoreFixture.instant(2026, 4),
            endsOn: StoreFixture.instant(2026, 9)
        )
        let shared = try await StoreFixture.course(in: database, terms: [winter, summer], name: "Informatik")
        let winterOnly = try await StoreFixture.course(in: database, terms: [winter], name: "Chemie")

        try await StoreFixture.recording(in: database, course: shared, term: winter, at: StoreFixture.instant(2025, 11, 3, 10, 0))
        try await StoreFixture.recording(in: database, course: winterOnly, term: winter, at: StoreFixture.instant(2025, 11, 4, 10, 0))
        try await StoreFixture.recording(in: database, course: shared, term: summer, at: StoreFixture.instant(2026, 5, 4, 10, 0))

        return (winter, summer, shared, winterOnly)
    }

    // MARK: - What the confirmation is told

    @Test("The count names every recording in the term and no others")
    func impactCountsOnlyThisTerm() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        let impact = try await repository.deletionImpact(of: try #require(year.winter.id))

        #expect(impact.recordings == 2)
        #expect(impact.isEmpty == false)
    }

    @Test("Only a course with nowhere else to be is named as lost")
    func impactNamesOnlyStrandedCourses() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        let impact = try await repository.deletionImpact(of: try #require(year.winter.id))

        // Informatik also runs in the summer and survives; Chemie does not.
        #expect(impact.coursesLost == ["Chemie"])
    }

    @Test("A term with nothing in it reports nothing lost")
    func impactOfAnEmptyTerm() async throws {
        let database = try StoreFixture.database()
        let empty = try await StoreFixture.term(in: database, title: "Fourth year, winter")
        let repository = LibraryRepository(database)

        let impact = try await repository.deletionImpact(of: try #require(empty.id))

        #expect(impact.isEmpty)
        #expect(impact.recordings == 0)
        #expect(impact.coursesLost.isEmpty)
    }

    // MARK: - What the deletion does

    @Test("The term and its recordings go, and the other term's do not")
    func deletingTakesOnlyItsOwnRecordings() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        try await repository.delete(term: try #require(year.winter.id))

        let terms = try await repository.terms()
        #expect(terms.map(\.id) == [year.summer.id])

        let remaining = try await database.writer.read { try Recording.fetchAll($0) }
        #expect(remaining.count == 1)
        #expect(remaining.first?.termID == year.summer.id)
    }

    @Test("A course that runs in another term survives with its recordings")
    func aSharedCourseSurvives() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        try await repository.delete(term: try #require(year.winter.id))

        let summer = try await repository.courses(in: try #require(year.summer.id))
        #expect(summer.map(\.course.name) == ["Informatik"])
        #expect(summer.first?.recordingCount == 1)
    }

    @Test("A course left with no term is removed rather than stranded")
    func aStrandedCourseIsRemoved() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        try await repository.delete(term: try #require(year.winter.id))

        let names = try await database.writer.read { try Course.fetchAll($0) }.map(\.name)
        // Chemie ran only in the winter. Left behind it would be a row in no
        // term, which no list in the app shows and nothing can record into.
        #expect(names == ["Informatik"])
    }

    // MARK: - Which term is current afterwards

    @Test("Deleting the current term makes another one current")
    func deletingTheCurrentTermPassesItOn() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        #expect(year.winter.isCurrent)
        try await repository.delete(term: try #require(year.winter.id))

        let current = try await repository.currentTerm()
        #expect(current?.id == year.summer.id)
    }

    @Test("Deleting a term that was not current leaves the current one alone")
    func deletingAnotherTermLeavesTheCurrentOne() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        try await repository.delete(term: try #require(year.summer.id))

        let current = try await repository.currentTerm()
        #expect(current?.id == year.winter.id)
    }

    @Test("Deleting the only term leaves no current term and no courses")
    func deletingTheLastTerm() async throws {
        let database = try StoreFixture.database()
        let only = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        try await StoreFixture.course(in: database, term: only, name: "Chemie")
        let repository = LibraryRepository(database)

        try await repository.delete(term: try #require(only.id))

        #expect(try await repository.terms().isEmpty)
        #expect(try await repository.currentTerm() == nil)
        #expect(try await database.writer.read { try Course.fetchCount($0) } == 0)
    }

    // MARK: - What the dialog says

    @Test("The body names the term, the count and what cannot be undone")
    func theBodyStatesTheLoss() {
        let term = Term(title: "Third year, winter")
        let sentences = DeleteTermDialog.sentences(
            for: term,
            impact: TermDeletion(recordings: 12, coursesLost: ["Chemie"])
        )

        #expect(sentences.contains("Third year, winter"))
        #expect(sentences.contains("12"))
        #expect(sentences.contains("Chemie"))
        #expect(sentences.contains("cannot be undone"))
    }

    @Test("One recording is written as one recording, not as 1 recordings")
    func theBodyIsWrittenForOne() {
        let sentences = DeleteTermDialog.sentences(
            for: Term(title: "Third year, winter"),
            impact: TermDeletion(recordings: 1, coursesLost: [])
        )

        #expect(sentences.contains("one recording"))
        #expect(!sentences.contains("1 recordings"))
    }

    @Test("A term that holds nothing is not warned about")
    func theBodyOfAnEmptyTermSaysSo() {
        let sentences = DeleteTermDialog.sentences(
            for: Term(title: "Third year, winter"),
            impact: TermDeletion(recordings: 0, coursesLost: [])
        )

        // Nothing is at stake, so the sentence that says something is must not
        // be there — a warning that fires every time is a warning nobody reads
        // on the one occasion it matters.
        #expect(!sentences.contains("cannot be undone"))
        #expect(sentences.contains("Third year, winter"))
    }
}
