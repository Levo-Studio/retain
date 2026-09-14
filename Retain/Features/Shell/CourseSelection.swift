import Foundation
import Observation

/// What the ready state's field is a picker for.
///
/// **The design draws a course name and a chevron and stops there.** It does
/// not draw the list that opens, what the field says before any course exists,
/// or what happens to the Record button then. All three are decided here, and
/// all three are decided the same way: a recording belongs to exactly one
/// course, so a course that cannot be named is a recording that cannot start.
///
/// The courses are the ones of the **current term** and nothing else, which is
/// the same filter board 05 puts on the library sidebar.
@MainActor
@Observable
final class CourseSelection {

    /// The term the courses come from. `nil` before the user has named one.
    private(set) var term: Term?

    /// The courses of that term, in the order the sidebar lists them.
    private(set) var courses: [Course] = []

    /// What the field shows. `nil` when there is nothing to show.
    private(set) var selected: Course?

    /// Whether the picker has been asked at least once, so the ready state can
    /// tell "no courses" from "not looked yet".
    private(set) var hasLoaded = false

    /// There is no recording without a course **and** without a term.
    ///
    /// A recording carries the term it was made in, and the one it carries is
    /// whichever was current when the microphone opened. With no current term
    /// there is no honest id to write, so the answer is no — refused here,
    /// where the Record button reads it, rather than guessed at the moment the
    /// row is opened.
    var canRecord: Bool { selected != nil && term?.id != nil }

    private let library: LibraryRepository?

    init(library: LibraryRepository? = nil) {
        self.library = library
    }

    /// A selection that is already made, with no database behind it.
    ///
    /// For rendering the ready state and for testing what the picker does with
    /// a term that has no courses in it — both of which are questions about the
    /// list, not about the store it came from.
    init(term: Term? = nil, courses: [Course], selected: Course?) {
        library = nil
        self.term = term
        self.courses = courses
        self.selected = selected
        hasLoaded = true
    }

    // MARK: - Reading

    /// Re-reads the current term and its courses.
    ///
    /// Called every time the popover opens rather than once at launch: a course
    /// created in the library window while the popover was closed has to be in
    /// the list the next time it opens, and the popover opening is exactly the
    /// moment that costs nothing.
    func reload() async {
        defer { hasLoaded = true }

        guard let library else { return }

        term = try? await library.currentTerm()
        guard let termID = term?.id else {
            courses = []
            selected = nil
            return
        }

        courses = ((try? await library.courses(in: termID)) ?? []).map(\.course)
        // A course that was deleted, or a term that was switched under us,
        // leaves the old selection pointing at nothing. Falling back to the
        // first course is what the field is drawn showing.
        if let selected, courses.contains(where: { $0.id == selected.id }) {
            self.selected = courses.first { $0.id == selected.id }
        } else {
            selected = courses.first
        }
    }

    /// Picks one of `courses`. Anything else is ignored — the field can only
    /// show a course of the current term.
    func select(_ course: Course) {
        guard courses.contains(where: { $0.id == course.id }) else { return }
        selected = course
    }
}
