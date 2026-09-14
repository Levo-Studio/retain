import Foundation
import Observation

/// Board 05, and the one thing it is really about: **the term is chosen once at
/// the top and everything under it is scoped to that choice.**
///
/// The picker in the title bar sets the term; the sidebar then holds the
/// courses of that term and no others; the table holds the recordings of the
/// course picked in that sidebar; and search covers that term and stops there.
/// A hit from a course somebody is not taking this half-year is noise, which is
/// why the scope is structural here rather than a filter that happens to be on.
@Observable
final class LibraryModel {

    // MARK: - What was loaded

    private(set) var terms: [Term] = []
    private(set) var courses: [CourseListing] = []
    private(set) var recordings: [Recording] = []

    private(set) var selectedTerm: Term?
    private(set) var selectedCourse: CourseListing?

    private(set) var isLoading = false

    // MARK: - Searching

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            search()
        }
    }

    private(set) var results: [SearchResultGroup] = []
    private(set) var isSearching = false

    private var searchTask: Task<Void, Never>?

    var isShowingResults: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Seams

    /// The new-course dialog is board 07 and belongs to the screen that owns
    /// the dialogs. The sidebar draws the row and calls this; nothing here
    /// knows what it opens.
    var onNewCourse: (() -> Void)?

    /// Renaming a term is board 07's "Name term" sheet, for the same reason.
    var onRenameTerm: ((Term) -> Void)?

    /// Opening a recording, optionally at a second — which is what a search hit
    /// is: a recording and a place in it.
    var onOpenRecording: ((Recording, TimeInterval?) -> Void)?

    // MARK: -

    private let database: RetainDatabase

    init(database: RetainDatabase) {
        self.database = database
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let library = LibraryRepository(database)
        do {
            terms = try await library.terms()
            // The picker opens on the term that was marked current, and on the
            // newest one before anything has been marked.
            let opening = try await library.currentTerm() ?? terms.first
            if let opening { await select(term: opening) }
        } catch {
            terms = []
        }
    }

    /// Choosing a term reloads everything under it, and makes that choice the
    /// one the window opens on next time.
    func select(term: Term) async {
        selectedTerm = term
        courses = []
        selectedCourse = nil
        recordings = []

        guard let termID = term.id else { return }

        let library = LibraryRepository(database)
        do {
            if !term.isCurrent {
                try await library.makeCurrent(termID)
                terms = try await library.terms()
                selectedTerm = terms.first { $0.id == termID } ?? term
            }
            courses = try await library.courses(in: termID)
            if let first = courses.first { await select(course: first) }
        } catch {
            courses = []
        }

        if isShowingResults { search() }
    }

    func select(course: CourseListing) async {
        selectedCourse = course
        guard let courseID = course.id else {
            recordings = []
            return
        }
        do {
            recordings = try await LibraryRepository(database).recordings(in: courseID)
        } catch {
            recordings = []
        }
    }

    /// Called after a course or a recording was added elsewhere — the
    /// new-course dialog, or a recording that has just stopped.
    func refresh() async {
        guard let term = selectedTerm, let termID = term.id else { return }
        let library = LibraryRepository(database)
        courses = (try? await library.courses(in: termID)) ?? courses

        if let selected = selectedCourse?.id,
           let again = courses.first(where: { $0.id == selected }) {
            await select(course: again)
        } else if let first = courses.first {
            await select(course: first)
        } else {
            selectedCourse = nil
            recordings = []
        }
    }

    // MARK: - Search

    private func search() {
        searchTask?.cancel()

        let asked = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, let termID = selectedTerm?.id else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [database] in
            let hits = (try? await SearchRepository(database).search(asked, in: termID)) ?? []
            guard !Task.isCancelled else { return }
            results = SearchResults.groups(from: hits)
            isSearching = false
        }
    }

    // MARK: - Derived

    /// "Oct 2025 – Mar 2026 · 4 courses" under the term's name.
    var termSubtitle: String {
        guard let term = selectedTerm else { return "" }
        let month = Date.FormatStyle.dateTime.month(.abbreviated).year()
        return LibraryCopy.termPeriod(
            from: term.startsOn.formatted(month),
            to: term.endsOn.formatted(month),
            courses: LibraryCopy.courses(courses.count)
        )
    }

    /// "Third year, winter · 9 recordings · 13 h 24 min" beside the course.
    /// The export also draws a teacher here; there is no teacher.
    var courseSubtitle: String {
        guard let course = selectedCourse, let term = selectedTerm else { return "" }
        return LibraryCopy.courseSummary(
            term: term.title,
            recordings: LibraryCopy.recordings(course.recordingCount),
            total: RecordingPresentation.total(course.totalDuration)
        )
    }

    func colour(of course: Course) -> Int { course.color.rawValue }

    func open(_ recording: Recording, at time: TimeInterval? = nil) {
        onOpenRecording?(recording, time)
    }

    /// A search hit is a recording and the second to start at, so following one
    /// needs the row behind it.
    func open(_ hit: SearchHit) async {
        guard let recording = try? await LibraryRepository(database).recording(hit.recordingID) else { return }
        open(recording, at: hit.time)
    }
}
