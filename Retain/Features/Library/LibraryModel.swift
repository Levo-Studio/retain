import Foundation
import GRDB
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


    // MARK: - Picking several at once

    /// Whether the recordings table is in selection mode.
    ///
    /// A mode rather than a modifier key, because the two things it leads to —
    /// deleting several lectures, and joining several into one — are both
    /// things somebody should have to mean. Leaving it clears what was ticked:
    /// a selection that survives being cancelled is a selection that acts on
    /// something later.
    private(set) var isSelecting = false

    /// The recordings ticked, by id.
    private(set) var selection: Set<Int64> = []

    /// The ticked recordings, in the order they were recorded — which is the
    /// order a merge lays them end to end in, so it is the order the
    /// confirmation has to show them in.
    var selectedRecordings: [Recording] {
        recordings
            .filter { $0.id.map(selection.contains) ?? false }
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// Two or more, none of them still running. One recording is already
    /// merged with itself, and the microphone is still writing into a running
    /// one.
    var canMergeSelection: Bool {
        let picked = selectedRecordings
        return picked.count > 1 && !picked.contains { $0.state == .recording }
    }

    var canDeleteSelection: Bool {
        let picked = selectedRecordings
        return !picked.isEmpty && !picked.contains { $0.state == .recording }
    }

    func startSelecting() {
        isSelecting = true
        selection = []
    }

    func stopSelecting() {
        isSelecting = false
        selection = []
    }

    func toggle(_ recording: Recording) {
        guard let id = recording.id else { return }
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func isSelected(_ recording: Recording) -> Bool {
        recording.id.map(selection.contains) ?? false
    }

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

    /// Starts a recording for the course the window is on.
    ///
    /// Filled in by the window controller, which is the only object that can
    /// see both the library and the shell. `nil` while there is no shell —
    /// the button is then drawn unavailable rather than doing nothing, which is
    /// the difference between a control that is off and one that is broken.
    var onRecord: ((Course, Term) -> Void)?

    /// Whether Retain is free to start one. Asked of the shell through a
    /// closure for the same reason as above.
    var canRecord: () -> Bool = { false }

    /// Ends the lecture that is running. `nil` while there is no shell.
    ///
    /// The library is where somebody sits during a lesson — it is the app's
    /// home window now — and the only way to stop a recording was to find the
    /// recording window again. One button, two states, in the place the reader
    /// already is.
    var onFinish: (() -> Void)?

    /// Whether a lecture is running at all.
    ///
    /// **Pushed in by the shell, not read through a closure.** A closure is
    /// invisible to `@Observable`, so the button would have kept saying Record
    /// for as long as the window stayed open, however many lectures started and
    /// stopped behind it.
    private(set) var isLectureRunning = false

    func lectureIsRunning(_ running: Bool) {
        guard running != isLectureRunning else { return }
        isLectureRunning = running
    }

    func finish() {
        onFinish?()
    }

    /// True when there is a course to record and nothing in the way.
    var isRecordable: Bool {
        selectedCourse != nil && selectedTerm?.id != nil && onRecord != nil && canRecord()
    }

    /// The verb behind the button.
    func record() {
        guard let course = selectedCourse?.course, let term = selectedTerm else { return }
        onRecord?(course, term)
    }

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

    /// Reads everything back after a dialog wrote something.
    ///
    /// The observation in `follow()` would deliver this on its own; it is still
    /// called directly so the sheet dismisses onto a sidebar that has already
    /// changed rather than one that changes a frame later.
    func reloadAfterEditing() async {
        await refresh()
    }

    /// Follows the library for as long as the window is open.
    ///
    /// **The window used to read once and keep what it read.** A course created
    /// in Settings did not appear here, a deleted term stayed in the picker,
    /// and the only way to see either was to quit Retain and open it again.
    ///
    /// The first element of the stream arrives immediately, so this is the
    /// window's load as well as its subscription — one code path rather than a
    /// load followed by a subscription with a gap between them.
    func follow() async {
        do {
            for try await _ in LibraryChanges.stream(in: database) {
                await refresh()
            }
        } catch {
            // The observation stopped. Read once more so the window is not left
            // showing whatever it happened to have.
            await refresh()
        }
    }

    /// Re-reads everything, **keeping what the user is looking at**.
    ///
    /// The difference from `load()` is the whole point: a course added in
    /// another window must not move the library off the course being read. The
    /// term and the course are kept when they still exist, and only fall back
    /// when they do not — which is what deleting them looks like from here.
    func refresh() async {
        let library = LibraryRepository(database)
        guard let all = try? await library.terms() else { return }
        terms = all

        // The term the window is already on wins, so a course added somewhere
        // else does not move the reader to another half-year. `??` cannot be
        // used for the fallbacks: its right side is an autoclosure, and one of
        // them is a database read.
        var opening = terms.first { $0.id == selectedTerm?.id }
        if opening == nil { opening = try? await library.currentTerm() }
        if opening == nil { opening = terms.first }

        guard let term = opening else {
            clearSelection()
            return
        }
        selectedTerm = term

        guard let termID = term.id else {
            clearSelection()
            return
        }
        courses = (try? await library.courses(in: termID)) ?? []

        if let course = courses.first(where: { $0.id == selectedCourse?.id }) ?? courses.first {
            await select(course: course)
        } else {
            selectedCourse = nil
            recordings = []
        }

        if isShowingResults { search() }
    }


    // MARK: - Loading

    private func clearSelection() {
        selectedTerm = nil
        courses = []
        selectedCourse = nil
        recordings = []
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
        // What was ticked belonged to the course being left. Carrying it would
        // mean a Delete that reaches into a course nobody is looking at.
        selection = []
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
    /// Counts what deleting a recording would cost, then opens the
    /// confirmation.
    ///
    /// Read before the sheet rather than inside it, so the dialog arrives able
    /// to say what is lost instead of filling the number in a frame later —
    /// which is a confirmation somebody can agree to before it has told them
    /// anything.
    func confirmDeletion(of recording: Recording) async {
        guard let impact = await LibraryEditing.impact(of: recording, in: libraryRepository) else { return }
        sheet = .deleteRecording(
            recording,
            courseName: selectedCourse?.course.name ?? "",
            impact: impact
        )
    }

    /// Counts what deleting a term would cost, then opens the confirmation.
    ///
    /// The count is read before the sheet rather than inside it, so the dialog
    /// arrives already able to say what is lost. Nothing opens if the count
    /// could not be read — a confirmation that cannot name the cost is worse
    /// than no confirmation.
    func confirmDeletion(of term: Term) async {
        guard let impact = await LibraryEditing.impact(of: term, in: libraryRepository) else { return }
        sheet = .deleteTerm(term, impact)
    }

    // MARK: - Acting on several at once

    /// Deletes every ticked recording, and the audio any of them still had.
    ///
    /// One at a time through the same path a single deletion takes, rather than
    /// one `DELETE ... IN (...)`: the file on disk is not the database's to
    /// remove, and the rule about a running lecture is written down once, in
    /// the repository. A batch that skipped either would be a second set of
    /// rules for the same act.
    func deleteSelection() async {
        let library = LibraryRepository(database)
        for recording in selectedRecordings {
            guard let id = recording.id else { continue }
            let filename = (try? await library.delete(recording: id)) ?? nil
            guard let filename, !filename.isEmpty else { continue }
            try? FileManager.default.removeItem(
                at: RecordingStore.directory.appendingPathComponent(filename)
            )
        }
        stopSelecting()
        await refresh()
    }

    /// Joins the ticked recordings into one, in the order they happened.
    ///
    /// The transaction is in the repository, where the rules about what
    /// survives are. What is left here is the part the database cannot do:
    /// unlinking the audio the emptied rows still had.
    func mergeSelection() async {
        guard canMergeSelection else { return }
        let ids = selectedRecordings.compactMap(\.id)

        guard let merged = try? await LibraryRepository(database).merge(recordings: ids) else {
            stopSelecting()
            return
        }

        for filename in merged.orphanedAudio where !filename.isEmpty {
            try? FileManager.default.removeItem(
                at: RecordingStore.directory.appendingPathComponent(filename)
            )
        }

        stopSelecting()
        await refresh()
    }

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
