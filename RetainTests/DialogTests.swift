import Foundation
import SwiftUI
import Testing

@testable import Retain

@Suite("Dialogs")
struct DialogTests {

    // MARK: - The colour picker

    @Test("The new-course dialog offers exactly four colours")
    func fourColours() {
        #expect(CourseColor.offered.count == 4)
        #expect(RetainPalette.courseColours.count == 4)
        #expect(RetainPalette.courseSwatches.count == 4)
    }

    /// The order is the storage: a course keeps its colour as this index, so
    /// reordering the list would silently repaint every course in the library.
    @Test("They are offered in the order the README lists them")
    func colourOrder() {
        #expect(CourseColor.offered == [.accent, .blue, .amber, .purple])
        #expect(CourseColor.offered.map(\.rawValue) == [0, 1, 2, 3])

        // The four `oklch()` values the README lists under "Accents", in the
        // order it lists them, converted the way the design layer converts
        // them. Four distinct hues, and the first is the accent.
        let expected = [
            RetainColor(OKLCH(0.78, 0.13, 165)),
            RetainColor(OKLCH(0.70, 0.11, 250)),
            RetainColor(OKLCH(0.75, 0.12, 70)),
            RetainColor(OKLCH(0.68, 0.10, 320)),
        ]
        #expect(RetainPalette.courseSwatches == expected)
        #expect(RetainPalette.accentValue == expected[0])
    }

    @Test("Every colour maps to its own swatch and none falls back")
    func everyColourHasASwatch() {
        for (index, colour) in CourseColor.offered.enumerated() {
            #expect(colour.swatch == RetainPalette.courseColours[index])
        }
        #expect(Set(RetainPalette.courseSwatches).count == 4)
    }

    // MARK: - The course draft

    @Test("A course needs a name and at least one term")
    func courseValidity() {
        #expect(!CourseDraft(name: "", termIDs: [1]).isSaveable)
        #expect(!CourseDraft(name: "   ", termIDs: [1]).isSaveable)
        #expect(!CourseDraft(name: "Computer networks", termIDs: []).isSaveable)
        #expect(CourseDraft(name: "Computer networks", termIDs: [1]).isSaveable)
        #expect(CourseDraft(name: "Computer networks", termIDs: [1, 2]).isSaveable)
    }

    /// The preselected term is a convenience for the two windows that already
    /// have one chosen, and `nil` really means none — not "the first one".
    @Test("Opening the dialog with no term ticks none")
    func courseDraftFromOneTerm() {
        #expect(CourseDraft(termID: 4).termIDs == [4])
        #expect(CourseDraft(termID: nil).termIDs.isEmpty)
    }

    @Test("Ticking a term adds it, ticking it again takes it away")
    func togglingTerms() {
        var draft = CourseDraft(name: "Computer science", termID: 1)
        draft.toggle(2)
        #expect(draft.termIDs == [1, 2])
        draft.toggle(1)
        #expect(draft.termIDs == [2])
        draft.toggle(2)
        #expect(draft.termIDs.isEmpty)
        #expect(!draft.isSaveable)
    }

    /// The row is the subject itself. Which terms it runs in is written beside
    /// it, in the join table, which is what lets one name serve both half-years.
    @Test("A saved course is trimmed and carries no term of its own")
    func courseRow() throws {
        let draft = CourseDraft(name: "  Computer networks ", termIDs: [7, 9], color: .amber)
        let course = try #require(draft.course())
        #expect(course.name == "Computer networks")
        #expect(course.color == .amber)
        #expect(draft.termIDs == [7, 9])
    }

    @Test("A course with no term ticked produces no row at all")
    func courseWithoutATermIsRefused() {
        #expect(CourseDraft(name: "Computer networks", termIDs: []).course() == nil)
    }

    /// Board 05 draws a teacher in the course header and no dialog offers a
    /// field for one. The owner settled it: there is no teacher.
    ///
    /// `id` is not a field of the course — it is which row is being edited,
    /// and it is nil for a course being created.
    @Test("A course has a name, its terms and a colour, and nothing else")
    func courseHasNoTeacher() {
        let mirror = Mirror(reflecting: CourseDraft())
        #expect(Set(mirror.children.compactMap(\.label)) == ["id", "name", "termIDs", "color"])
    }

    // MARK: - The term draft

    @Test("A term needs a name, and a period it has both ends of must run forwards")
    func termValidity() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(!TermDraft(title: "", startsOn: start, endsOn: start).isSaveable)
        #expect(!TermDraft(title: "  ", startsOn: start, endsOn: start).isSaveable)
        #expect(TermDraft(title: "Third year, winter", startsOn: start, endsOn: start).isSaveable)
        #expect(
            !TermDraft(
                title: "Backwards",
                startsOn: start.addingTimeInterval(60 * 60 * 24 * 90),
                endsOn: start
            ).isSaveable
        )
    }

    /// The period is a caption and nothing computes with it, so every shape of
    /// it saves — including the one the dialog now opens with.
    @Test("A term with half a period, or none at all, is still saveable")
    func termWithoutAPeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(TermDraft(title: "Third year, winter").isSaveable)
        #expect(TermDraft(title: "Third year, winter", startsOn: start).isSaveable)
        #expect(TermDraft(title: "Third year, winter", endsOn: start).isSaveable)
        #expect(!TermDraft(title: "   ").isSaveable)
    }

    @Test("A term the dialog was opened fresh for has no period in it")
    func aNewDraftHasNoPeriod() {
        let draft = TermDraft()
        #expect(draft.startsOn == nil)
        #expect(draft.endsOn == nil)
        #expect(draft.term().startsOn == nil)
        #expect(draft.term().endsOn == nil)
    }

    /// Against the current calendar, which is the one the draft normalises
    /// with: the claim is that half a period is normalised exactly as a whole
    /// one is, not anything about a particular time zone.
    @Test("An endpoint that is there is still normalised to its month")
    func halfAPeriodIsStillMonths() {
        let middleOfOctober = Date(timeIntervalSinceReferenceDate: 781_100_520)
        let draft = TermDraft(title: "Third year, winter", startsOn: middleOfOctober)

        #expect(draft.startsOn == TermMonth.normalised(middleOfOctober))
        #expect(draft.term().startsOn == TermMonth.normalised(middleOfOctober))
        #expect(draft.term().endsOn == nil)
    }

    @Test("A period is kept at month granularity")
    func periodIsMonths() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let middleOfOctober = try #require(
            calendar.date(from: DateComponents(year: 2025, month: 10, day: 17, hour: 13, minute: 42))
        )
        let normalised = TermMonth.normalised(middleOfOctober, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: normalised)

        #expect(parts.year == 2025)
        #expect(parts.month == 10)
        #expect(parts.day == 1)
        #expect(parts.hour == 0)
        #expect(parts.minute == 0)
    }

    @Test("The month picker offers a run of months around the one it is given")
    func monthChoices() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let anchor = try #require(calendar.date(from: DateComponents(year: 2025, month: 10)))

        let choices = TermMonth.choices(around: anchor, calendar: calendar)

        #expect(choices.count == 61)
        #expect(choices.contains(anchor))
        #expect(Set(choices).count == choices.count)
        #expect(choices == choices.sorted())
    }

    /// At most one term is current and the database enforces it. The row built
    /// from a draft therefore never carries the flag: it is set afterwards,
    /// through the one transaction that clears the old one first.
    @Test("The row a draft builds never claims to be current")
    func draftRowIsNeverCurrent() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let draft = TermDraft(title: "Third year, winter", startsOn: start, endsOn: start, isCurrent: true)
        #expect(draft.isCurrent)
        #expect(draft.term().isCurrent == false)
    }

    @Test("A title is trimmed on the way into the row")
    func titleIsTrimmed() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(TermDraft(title: "  Third year  ", startsOn: start, endsOn: start).term().title == "Third year")
    }

    // MARK: - At most one current term

    @Test("Turning a term current says which one stops being it")
    func displacedTerm() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let existing = Term(id: 1, title: "Second year, summer", startsOn: start, endsOn: start, isCurrent: true)
        let draft = TermDraft(id: 2, title: "Third year, winter", startsOn: start, endsOn: start, isCurrent: true)

        let displaced = try #require(CurrentTerm.displaced(by: draft, among: [existing]))
        #expect(displaced.id == 1)
        #expect(CurrentTerm.warning(displacing: displaced) == "Second year, summer stops being the current term.")
    }

    @Test("A term that is already the current one displaces nothing")
    func noSelfDisplacement() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let existing = Term(id: 1, title: "Third year, winter", startsOn: start, endsOn: start, isCurrent: true)
        let draft = TermDraft(existing)
        #expect(CurrentTerm.displaced(by: draft, among: [existing]) == nil)
    }

    @Test("A draft that is not current displaces nothing")
    func notCurrentDisplacesNothing() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let existing = Term(id: 1, title: "Second year, summer", startsOn: start, endsOn: start, isCurrent: true)
        let draft = TermDraft(id: 2, title: "Third year, winter", startsOn: start, endsOn: start, isCurrent: false)
        #expect(CurrentTerm.displaced(by: draft, among: [existing]) == nil)
    }

    @Test("With nothing to displace the toggle says what the export says")
    func drawnCaption() {
        #expect(CurrentTerm.caption == "shown as selected at the top")
    }

    /// The dialog's promise, checked against the schema rather than against
    /// itself: saving through the draft's own row and then `makeCurrent(_:)`
    /// leaves exactly one current term, where writing `isCurrent = true`
    /// directly would hit the partial unique index.
    @Test("Saving a second current term through the dialog's path leaves one")
    func savingKeepsOneCurrentTerm() async throws {
        let database = try StoreFixture.database()
        let repository = LibraryRepository(database)

        let first = try await repository.save(
            Term(title: "Second year, summer", startsOn: .now, endsOn: .now)
        )
        try await repository.makeCurrent(try #require(first.id))

        let draft = TermDraft(title: "Third year, winter", startsOn: .now, endsOn: .now, isCurrent: true)
        let saved = try await repository.save(draft.term())
        try await repository.makeCurrent(try #require(saved.id))

        let terms = try await repository.terms()
        #expect(terms.filter(\.isCurrent).count == 1)
        #expect(try await repository.currentTerm()?.id == saved.id)
    }

    // MARK: - Term kind

    @Test("A term is a half-year or a semester, and nothing else")
    func termKinds() {
        #expect(TermKind.allCases == [.halfYear, .semester])
        #expect(TermKind.halfYear.title == "Half-year")
        #expect(TermKind.semester.title == "Semester")
    }

    @Test("A new term is a half-year until somebody says otherwise")
    func defaultKind() {
        #expect(TermDraft(startsOn: .now, endsOn: .now).kind == .halfYear)
    }

    @Test("The kind survives the draft round trip")
    func kindRoundTrips() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let term = Term(id: 3, title: "First semester", kind: .semester, startsOn: start, endsOn: start)
        #expect(TermDraft(term).kind == .semester)
        #expect(TermDraft(term).term().kind == .semester)
    }

    // MARK: - The unreachable dialog

    /// The body says the recording keeps running and the summaries are caught
    /// up. The address it names is the one the user typed, stripped of anything
    /// that could be a secret.
    @Test("The dialog names the server and not what was pasted in front of it")
    func unreachableDialogAddress() {
        #expect(BaseAddress.displayed("http://localhost:1234/v1") == "http://localhost:1234/v1")
        #expect(BaseAddress.displayed("http://sk-key@localhost:1234/v1") == "http://localhost:1234/v1")
    }
}

// MARK: -

/// Before this, a course's name and the terms it ran in were settled the moment
/// it was created and never again: a typo in "Informatik" was permanent, and
/// "it also runs in the summer" could only be said by making a second course
/// that shares nothing with the first — which is the opposite of what one
/// course in several terms is for.
@Suite("Editing a course")
struct CourseEditingTests {

    private func course(_ name: String = "Informatik", id: Int64? = 7) -> Course {
        Course(id: id, name: name, color: .accent)
    }

    @Test("A draft for an existing course carries its identity, name, colour and terms")
    func draftRemembersTheCourse() {
        let draft = CourseDraft(editing: course(), termIDs: [1, 2])

        #expect(draft.isEditing)
        #expect(draft.id == 7)
        #expect(draft.name == "Informatik")
        #expect(draft.termIDs == [1, 2])
        #expect(draft.course()?.id == 7, "the write has to land on the row that exists")
    }

    @Test("A draft for a new course has no identity")
    func newDraftHasNone() {
        let draft = CourseDraft(termID: 1)
        #expect(!draft.isEditing)
        #expect(draft.course()?.id == nil)
    }

    @Test("Renaming renames the one course, in every term it runs in")
    func renamingReachesEveryTerm() async throws {
        let database = try StoreFixture.database()
        let library = LibraryRepository(database)

        let winter = try await StoreFixture.term(in: database, title: "Winter", isCurrent: true)
        let summer = try await StoreFixture.term(in: database, title: "Summer")
        let ids = try #require(Set([winter.id, summer.id].compactMap { $0 }) as Set<Int64>?)

        let created = try #require(
            await LibraryEditing.create(CourseDraft(name: "Infromatik", termIDs: ids), in: library)
        )

        var draft = CourseDraft(editing: created, termIDs: ids)
        draft.name = "Informatik"
        await LibraryEditing.update(draft, in: library)

        for termID in ids {
            let names = try await library.courses(in: termID).map(\.course.name)
            #expect(names == ["Informatik"], "the typo survived in one of the terms")
        }
    }

    @Test("Adding a term adds the course to it and leaves the other alone")
    func addingATermKeepsTheRest() async throws {
        let database = try StoreFixture.database()
        let library = LibraryRepository(database)

        let winter = try await StoreFixture.term(in: database, title: "Winter", isCurrent: true)
        let summer = try await StoreFixture.term(in: database, title: "Summer")
        let winterID = try #require(winter.id)
        let summerID = try #require(summer.id)

        let created = try #require(
            await LibraryEditing.create(CourseDraft(name: "Informatik", termIDs: [winterID]), in: library)
        )
        let courseID = try #require(created.id)

        #expect(try await library.courses(in: summerID).isEmpty)

        var draft = CourseDraft(editing: created, termIDs: [winterID, summerID])
        draft.termIDs = [winterID, summerID]
        await LibraryEditing.update(draft, in: library)

        #expect(try await library.courses(in: winterID).count == 1)
        #expect(try await library.courses(in: summerID).count == 1)
        #expect(try await library.terms(of: courseID).count == 2)
    }

    /// The dialog and the repository both refuse it; this is the dialog's half.
    @Test("Unticking every term is refused rather than orphaning the course")
    func aCourseInNoTermIsRefused() async throws {
        let database = try StoreFixture.database()
        let library = LibraryRepository(database)

        let term = try await StoreFixture.term(in: database, isCurrent: true)
        let termID = try #require(term.id)
        let created = try #require(
            await LibraryEditing.create(CourseDraft(name: "Informatik", termIDs: [termID]), in: library)
        )

        var draft = CourseDraft(editing: created, termIDs: [])
        draft.termIDs = []

        #expect(!draft.isSaveable)
        #expect(await LibraryEditing.update(draft, in: library) == nil)
        #expect(try await library.courses(in: termID).count == 1, "the course is still where it was")
    }
}

// MARK: -

/// The first term was the only one that could ever be created. The General
/// pane's term row had one button that said "New term" while there were none
/// and "Rename" as soon as there was one, so a second half-year was
/// unreachable from anywhere in the app — and the row looked complete while
/// being a dead end.
@Suite("Creating more than one term")
struct SecondTermTests {

    @Test("A term draft with nothing in it is a new term, not a rename")
    func emptyDraftCreates() {
        let draft = TermDraft()
        #expect(draft.term().id == nil, "a draft with no identity writes a new row")
    }

    @Test("A draft made from a term renames that term")
    func draftFromTermRenames() async throws {
        let database = try StoreFixture.database()
        let library = LibraryRepository(database)
        let term = try await StoreFixture.term(in: database, title: "Winter", isCurrent: true)

        var draft = TermDraft(term)
        draft.title = "Third year, winter"
        await LibraryEditing.save(draft, in: library)

        let all = try await library.terms()
        #expect(all.count == 1, "renaming must not create a second term")
        #expect(all.first?.title == "Third year, winter")
    }

    @Test("Several terms can exist side by side, and only one is current")
    func manyTermsOneCurrent() async throws {
        let database = try StoreFixture.database()
        let library = LibraryRepository(database)

        for (title, isCurrent) in [("Winter", true), ("Summer", false), ("Next winter", false)] {
            var draft = TermDraft()
            draft.title = title
            draft.isCurrent = isCurrent
            await LibraryEditing.save(draft, in: library)
        }

        let all = try await library.terms()
        #expect(all.count == 3)
        #expect(all.filter(\.isCurrent).count == 1)
        #expect(Set(all.map(\.title)) == ["Winter", "Summer", "Next winter"])
    }

    /// The database enforces at most one current term with a partial unique
    /// index, so making a later one current has to clear the earlier one rather
    /// than fail.
    @Test("Making a later term current releases the earlier one")
    func currentMovesRatherThanCollides() async throws {
        let database = try StoreFixture.database()
        let library = LibraryRepository(database)

        var winter = TermDraft()
        winter.title = "Winter"
        winter.isCurrent = true
        await LibraryEditing.save(winter, in: library)

        var summer = TermDraft()
        summer.title = "Summer"
        summer.isCurrent = true
        await LibraryEditing.save(summer, in: library)

        let all = try await library.terms()
        #expect(all.count == 2)
        #expect(all.filter(\.isCurrent).map(\.title) == ["Summer"])
    }
}
