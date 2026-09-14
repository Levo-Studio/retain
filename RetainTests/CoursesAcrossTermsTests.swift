import Foundation
import GRDB
import Testing

@testable import Retain

/// The same school subject runs in the winter half-year and in the summer one,
/// and it is **one course**.
///
/// What that has to buy: one name to rename, one colour, and two entirely
/// separate sets of recordings — pick the other term at the top of board 05 and
/// the course is still there with that term's work under it and nothing from
/// the other one.
@Suite("Courses across terms")
struct CoursesAcrossTermsTests {

    /// Winter and summer, with one course in both and one recording in each.
    private func year(
        in database: RetainDatabase
    ) async throws -> (winter: Term, summer: Term, course: Course, winterRecording: Recording, summerRecording: Recording) {
        let winter = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let summer = try await StoreFixture.term(
            in: database,
            title: "Third year, summer",
            startsOn: StoreFixture.instant(2026, 4),
            endsOn: StoreFixture.instant(2026, 9)
        )
        let course = try await StoreFixture.course(in: database, terms: [winter, summer], name: "Informatik")

        return (
            winter,
            summer,
            course,
            try await StoreFixture.recording(
                in: database,
                course: course,
                term: winter,
                at: StoreFixture.instant(2025, 11, 3, 10, 0)
            ),
            try await StoreFixture.recording(
                in: database,
                course: course,
                term: summer,
                at: StoreFixture.instant(2026, 5, 4, 10, 0)
            )
        )
    }

    // MARK: - One course, two terms

    @Test("A course in two terms is one row and shows up in both")
    func oneCourseInTwoTerms() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        let winter = try await repository.courses(in: try #require(year.winter.id))
        let summer = try await repository.courses(in: try #require(year.summer.id))

        #expect(winter.map(\.course.id) == [year.course.id])
        #expect(summer.map(\.course.id) == [year.course.id])
        // One row, not one per half-year — which is the whole point.
        #expect(try await database.writer.read { try Course.fetchCount($0) } == 1)
    }

    @Test("Renaming a course renames it in every term it runs in")
    func renamingReachesBothTerms() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        var course = year.course
        course.name = "Computer science"
        course.color = .purple
        try await repository.save(course)

        for term in [year.winter, year.summer] {
            let termID = try #require(term.id)
            let listing = try #require(try await repository.courses(in: termID).first)
            #expect(listing.course.name == "Computer science")
            #expect(listing.course.color == .purple)
        }
    }

    @Test("The same course cannot be put into the same term twice")
    func aCourseIsInATermAtMostOnce() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let courseID = try #require(year.course.id)
        let termID = try #require(year.winter.id)

        // The guarantee is the unique index, not a check the repository makes
        // first, so a second way of writing the row runs into it too.
        await #expect(throws: DatabaseError.self) {
            try await database.writer.write { db in
                var duplicate = CourseTerm(courseID: courseID, termID: termID)
                try duplicate.insert(db)
            }
        }

        #expect(try await LibraryRepository(database).terms(of: courseID).count == 2)
    }

    @Test("A course belongs to no term only if it is refused outright")
    func aCourseWithoutATermIsRefused() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)

        await #expect(throws: RetainDatabaseError.courseWithoutTerm) {
            try await repository.create(Course(name: "Informatik", color: .accent), in: [])
        }

        // And it refused before writing anything, rather than leaving a course
        // nothing in the interface can reach.
        #expect(try await database.writer.read { try Course.fetchCount($0) } == 0)
    }

    @Test("Changing which terms a course runs in leaves its recordings alone")
    func settingTermsKeepsRecordings() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)
        let courseID = try #require(year.course.id)
        let winterID = try #require(year.winter.id)

        try await repository.setTerms(of: courseID, to: [winterID])

        let summerID = try #require(year.summer.id)
        let summerRecordingID = try #require(year.summerRecording.id)

        #expect(try await repository.terms(of: courseID).map(\.id) == [year.winter.id])
        #expect(try await repository.courses(in: summerID).isEmpty)
        // The summer recording still exists and still knows which term it was
        // made in. Dropping a course out of a term is not a deletion.
        let summerRecording = try #require(try await repository.recording(summerRecordingID))
        #expect(summerRecording.termID == summerID)
    }

    // MARK: - Per-term content

    @Test("A course's recordings are the selected term's, and nothing leaks across")
    func recordingsAreScopedToCourseAndTerm() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        let winter = try await repository.recordings(
            in: try #require(year.course.id),
            during: try #require(year.winter.id)
        )
        let summer = try await repository.recordings(
            in: try #require(year.course.id),
            during: try #require(year.summer.id)
        )

        #expect(winter.map(\.id) == [year.winterRecording.id])
        #expect(summer.map(\.id) == [year.summerRecording.id])
    }

    @Test("The count beside a course in the sidebar is that term's, not the course's")
    func theSidebarCountsOneTerm() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)

        // A second winter recording, so the two half-years differ.
        var extra = try await StoreFixture.recording(
            in: database,
            course: year.course,
            term: year.winter,
            at: StoreFixture.instant(2025, 11, 10, 10, 0)
        )
        extra.duration = 45 * 60
        try await repository.save(extra)

        let winterID = try #require(year.winter.id)
        let summerID = try #require(year.summer.id)
        let winter = try #require(try await repository.courses(in: winterID).first)
        let summer = try #require(try await repository.courses(in: summerID).first)

        #expect(winter.recordingCount == 2)
        #expect(winter.totalDuration == 45 * 60)
        #expect(summer.recordingCount == 1)
        #expect(summer.totalDuration == 0)
    }

    @Test("A course with nothing recorded in this term still has a row, reading zero")
    func anEmptyTermStillListsTheCourse() async throws {
        let database = try StoreFixture.database()
        let winter = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let summer = try await StoreFixture.term(
            in: database,
            title: "Third year, summer",
            startsOn: StoreFixture.instant(2026, 4),
            endsOn: StoreFixture.instant(2026, 9)
        )
        let course = try await StoreFixture.course(in: database, terms: [winter, summer], name: "Informatik")
        try await StoreFixture.recording(in: database, course: course, term: winter)

        let summerID = try #require(summer.id)
        let listing = try #require(try await LibraryRepository(database).courses(in: summerID).first)
        #expect(listing.course.name == "Informatik")
        #expect(listing.recordingCount == 0)
        #expect(listing.totalDuration == 0)
    }

    // MARK: - Deleting a term

    @Test("Deleting a term takes the course out of it and leaves the course standing")
    func deletingATermKeepsTheCourse() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)
        let courseID = try #require(year.course.id)
        let summerID = try #require(year.summer.id)

        try await database.writer.write { db in
            _ = try Term.deleteOne(db, key: summerID)
        }

        #expect(try await repository.course(courseID)?.name == "Informatik")
        #expect(try await repository.terms(of: courseID).map(\.id) == [year.winter.id])
        #expect(try await repository.courses(in: try #require(year.winter.id)).count == 1)

        // The winter side is untouched, which is what "takes the link and not
        // the course" has to mean in practice.
        let winter = try await repository.recordings(
            in: courseID,
            during: try #require(year.winter.id)
        )
        #expect(winter.map(\.id) == [year.winterRecording.id])
    }

    // MARK: - The term a recording was made in

    @Test("Editing a term's period moves no recordings")
    func aRecordingKeepsItsTermWhenThePeriodChanges() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)
        let repository = LibraryRepository(database)
        let recordingID = try #require(year.winterRecording.id)

        // The period is a caption: emptying it, or moving it past the day the
        // recording was made, changes nothing about where the recording is
        // filed. A term derived from dates would have lost it here.
        var winter = year.winter
        winter.startsOn = StoreFixture.instant(2030, 1)
        winter.endsOn = nil
        try await repository.save(winter)

        #expect(try await repository.recording(recordingID)?.termID == year.winter.id)

        let still = try await repository.recordings(
            in: try #require(year.course.id),
            during: try #require(year.winter.id)
        )
        #expect(still.map(\.id) == [recordingID])
    }

    // MARK: - The library window

    @Test("Switching the term keeps the course and swaps everything under it")
    @MainActor
    func switchingTermsSwapsTheContent() async throws {
        let database = try StoreFixture.database()
        let year = try await year(in: database)

        let model = LibraryModel(database: database)
        await model.load()

        #expect(model.selectedTerm?.id == year.winter.id)
        #expect(model.courses.map(\.course.name) == ["Informatik"])
        #expect(model.recordings.map(\.id) == [year.winterRecording.id])

        await model.select(term: year.summer)

        // The course stays, the content starts again from that term's own rows.
        #expect(model.selectedTerm?.id == year.summer.id)
        #expect(model.courses.map(\.course.id) == [year.course.id])
        #expect(model.recordings.map(\.id) == [year.summerRecording.id])

        await model.select(term: year.winter)
        #expect(model.recordings.map(\.id) == [year.winterRecording.id])
    }
}
