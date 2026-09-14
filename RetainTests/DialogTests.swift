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

    @Test("A course needs a name and a term")
    func courseValidity() {
        #expect(!CourseDraft(name: "", termID: 1).isSaveable)
        #expect(!CourseDraft(name: "   ", termID: 1).isSaveable)
        #expect(!CourseDraft(name: "Computer networks", termID: nil).isSaveable)
        #expect(CourseDraft(name: "Computer networks", termID: 1).isSaveable)
    }

    @Test("A saved course is trimmed and keeps its term and colour")
    func courseRow() throws {
        let course = try #require(CourseDraft(name: "  Computer networks ", termID: 7, color: .amber).course())
        #expect(course.name == "Computer networks")
        #expect(course.termID == 7)
        #expect(course.color == .amber)
    }

    /// Board 05 draws a teacher in the course header and no dialog offers a
    /// field for one. The owner settled it: there is no teacher.
    @Test("A course has a name, a term and a colour, and nothing else")
    func courseHasNoTeacher() {
        let mirror = Mirror(reflecting: CourseDraft())
        #expect(Set(mirror.children.compactMap(\.label)) == ["name", "termID", "color"])
    }

    // MARK: - The term draft

    @Test("A term needs a name and a period that runs forwards")
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
