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

    /// Which of board 07's editing dialogs is open over the window.
    ///
    /// Held here rather than passed in as a closure. It was a closure, and the
    /// window controller never filled it in — so the sidebar's two buttons did
    /// nothing at all, which is indistinguishable from a broken app and was
    /// exactly how it was reported.
    var sheet: LibrarySheet?

    /// Opening a recording, optionally at a second — which is what a search hit
    /// is: a recording and a place in it.
    var onOpenRecording: ((Recording, TimeInterval?) -> Void)?

    // MARK: -

    private let database: RetainDatabase

    /// For the editing dialogs, which write rather than read.
    var libraryRepository: LibraryRepository { LibraryRepository(database) }

    init(database: RetainDatabase) {
        self.database = database
    }

    /// Reads everything back after a dialog wrote something. A sheet that
    /// dismisses onto a stale sidebar is the same bug as one that did nothing.
    func reloadAfterEditing() async {
        await load()
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

    /// The table is this course **in the term that is selected**, and the term
    /// is half the question rather than context: the same course in the other
    /// half-year is a different set of recordings and different notes, and
    /// nothing is shared between them but the name and the colour.
    func select(course: CourseListing) async {
        selectedCourse = course
        guard let courseID = course.id, let termID = selectedTerm?.id else {
            recordings = []
            return
        }
        do {
            recordings = try await LibraryRepository(database).recordings(in: courseID, during: termID)
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

    /// "Oct 2025 – Mar 2026 · 4 courses" under the term's name — and "4 courses"
    /// on its own for a term nobody gave a period.
    var termSubtitle: String {
        guard let term = selectedTerm else { return "" }
        return LibraryCopy.termSubtitle(
            period: TermPeriod.caption(of: term),
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

    /// Opens the edit dialog for a course, with the terms it runs in already
    /// ticked.
    ///
    /// Read here rather than in the view: the chips have to arrive correct
    /// rather than filling in a frame later, and the view has no repository.
    func edit(_ course: Course) async {
        guard let id = course.id else { return }
        let termIDs = Set((try? await libraryRepository.terms(of: id))?.compactMap(\.id) ?? [])
        sheet = .editCourse(course, termIDs: termIDs)
    }

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
