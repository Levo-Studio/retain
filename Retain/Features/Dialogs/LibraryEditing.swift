import SwiftUI

/// Which of board 07's two editing dialogs is open.
///
/// Shared between Settings and the Library because both offer the same two
/// actions — the General pane has "New term" and "New course", the library
/// sidebar has "Rename" and "+ New course" — and they must do the same thing.
/// Two copies would be two places for the term's is-current rule to be got
/// wrong.
nonisolated enum LibrarySheet: Identifiable, Equatable, Sendable {

    /// `nil` creates a term rather than renaming one.
    case nameTerm(Term?)

    /// The term ticked when the dialog opens — the one the window already has
    /// selected. The user can tick more, or untick this one; `nil` opens with
    /// none ticked, and the dialog then refuses to create anything.
    case newCourse(Int64?)

    /// An existing course, with the terms it already runs in.
    ///
    /// The same dialog as `newCourse`. Without it a course's name and its terms
    /// were settled at the moment it was created and never again — so a typo in
    /// "Informatik" was permanent, and "it also runs in the summer" could only
    /// be said by making a second course that shares nothing with the first.
    case editCourse(Course, termIDs: Set<Int64>)

    /// A term and what deleting it would cost, counted before the sheet opens.
    ///
    /// The cost travels in the case rather than being read inside the dialog
    /// because the dialog is the last thing between a lecture and no lecture:
    /// a sheet that opens saying "0 recordings" and fills the real number in a
    /// frame later is a sheet somebody can confirm before it has told them
    /// anything.
    case deleteTerm(Term, TermDeletion)

    /// One recording, the course it belongs to, and what deleting it would
    /// cost. The course name travels with it because "Delete recording" alone
    /// does not say which lecture is about to go.
    case deleteRecording(Recording, courseName: String, impact: RecordingDeletion)

    var id: String {
        switch self {
        case .nameTerm(let term): "term-\(term?.id ?? 0)"
        case .newCourse(let termID): "course-\(termID ?? 0)"
        case .editCourse(let course, _): "edit-course-\(course.id ?? 0)"
        case .deleteTerm(let term, _): "delete-term-\(term.id ?? 0)"
        case .deleteRecording(let recording, _, _): "delete-recording-\(recording.id ?? 0)"
        }
    }
}

// MARK: - Writing what the dialogs produce

/// The two writes behind board 07's editing dialogs.
///
/// Here rather than in a view because both windows perform them, and because
/// the term write has a rule in it that is easy to get wrong once and
/// impossible to notice twice.
@MainActor
enum LibraryEditing {

    /// Saving a term is two statements, never one.
    ///
    /// The row is written with `isCurrent` cleared, and the flag is then set
    /// through `makeCurrent(_:)`, which clears the old one and sets the new one
    /// inside a single transaction. Writing `isCurrent = true` directly would
    /// hit the partial unique index and fail — which is the database doing its
    /// job, not something to work around by dropping the index.
    @discardableResult
    static func save(_ draft: TermDraft, in library: LibraryRepository) async -> Term? {
        guard let saved = try? await library.save(draft.term()), let id = saved.id else { return nil }
        if draft.isCurrent {
            try? await library.makeCurrent(id)
        }
        return saved
    }

    /// The course row and the terms it runs in, in one transaction.
    ///
    /// `draft.course()` is `nil` for a draft with no term ticked, so a course
    /// that belongs nowhere is refused here as well as by the disabled Create
    /// button — and again by the repository, which is reachable without either.
    @discardableResult
    static func create(_ draft: CourseDraft, in library: LibraryRepository) async -> Course? {
        guard let course = draft.course() else { return nil }
        return try? await library.create(course, in: draft.termIDs)
    }

    /// The name, the colour and the terms, in that order.
    ///
    /// Two writes rather than one because they are two things: `save` carries
    /// the row, `setTerms` carries the pairings. Renaming a course renames it
    /// in every term it runs in — that is the whole point of one course being
    /// in several — and removing a term unlinks it without touching the
    /// recordings made in the ones that remain.
    /// Deletes a term and everything the confirmation said would go with it.
    ///
    /// Thin on purpose: every rule about what a deletion takes — the cascade,
    /// the courses left stranded, which term becomes current afterwards — is
    /// in the one transaction in `LibraryRepository`, where it is written once
    /// and tested without a view.
    static func delete(_ term: Term, in library: LibraryRepository) async {
        guard let id = term.id else { return }
        try? await library.delete(term: id)
    }

    /// Deletes a recording, and the audio file if there still is one.
    ///
    /// Two steps because they are two stores: the row and everything cascading
    /// off it go in one transaction, and the file on disk is unlinked
    /// afterwards using the name that transaction handed back. A file left
    /// behind would be a recording nothing will ever read again.
    static func delete(_ recording: Recording, in library: LibraryRepository) async {
        guard let id = recording.id else { return }

        // `try?` on a call that already returns an optional gives a double
        // optional: the outer is "the write threw", the inner is "there was no
        // file". Flattened here rather than nested, because they mean the same
        // thing to this function — nothing to unlink.
        let filename = (try? await library.delete(recording: id)) ?? nil
        guard let filename, !filename.isEmpty else { return }

        try? FileManager.default.removeItem(
            at: RecordingStore.directory.appendingPathComponent(filename)
        )
    }

    /// Reads what deleting a recording would cost.
    static func impact(of recording: Recording, in library: LibraryRepository) async -> RecordingDeletion? {
        guard let id = recording.id else { return nil }
        return try? await library.deletionImpact(ofRecording: id)
    }

    /// Reads what a deletion would cost, for the sheet that is about to ask.
    ///
    /// `nil` when the count could not be read, and the caller then opens
    /// nothing: a confirmation that cannot say what is lost has no business
    /// being shown.
    static func impact(of term: Term, in library: LibraryRepository) async -> TermDeletion? {
        guard let id = term.id else { return nil }
        return try? await library.deletionImpact(of: id)
    }

    @discardableResult
    static func update(_ draft: CourseDraft, in library: LibraryRepository) async -> Course? {
        guard let course = draft.course(), let id = course.id else { return nil }
        guard let saved = try? await library.save(course) else { return nil }
        try? await library.setTerms(of: id, to: draft.termIDs)
        return saved
    }
}

// MARK: - Presenting them

extension View {

    /// Puts board 07's editing dialogs over a window.
    ///
    /// `reload` runs after a write rather than the caller watching the
    /// database: both windows hold their own loaded lists, and a sheet that
    /// dismisses onto a stale sidebar is the same bug as one that does nothing.
    func libraryEditingSheet(
        _ sheet: Binding<LibrarySheet?>,
        terms: [Term],
        library: LibraryRepository?,
        reload: @escaping () async -> Void
    ) -> some View {
        self.sheet(item: sheet) { which in
            Group {
                switch which {
                case .nameTerm(let term):
                    NameTermDialog(
                        terms: terms,
                        // A new term opens with no period. It is optional, and
                        // prefilling both fields with this month would make a
                        // date the user never picked look like one they did.
                        draft: term.map(TermDraft.init) ?? TermDraft(),
                        save: { draft in
                            sheet.wrappedValue = nil
                            guard let library else { return }
                            Task {
                                await LibraryEditing.save(draft, in: library)
                                await reload()
                            }
                        },
                        cancel: { sheet.wrappedValue = nil }
                    )

                case .newCourse(let termID):
                    CourseDialog(
                        terms: terms,
                        draft: CourseDraft(termID: termID),
                        confirm: { draft in
                            sheet.wrappedValue = nil
                            guard let library else { return }
                            Task {
                                await LibraryEditing.create(draft, in: library)
                                await reload()
                            }
                        },
                        cancel: { sheet.wrappedValue = nil }
                    )

                case .deleteTerm(let term, let impact):
                    DeleteTermDialog(
                        term: term,
                        impact: impact,
                        delete: {
                            sheet.wrappedValue = nil
                            guard let library else { return }
                            Task {
                                await LibraryEditing.delete(term, in: library)
                                await reload()
                            }
                        },
                        cancel: { sheet.wrappedValue = nil }
                    )

                case .deleteRecording(let recording, let courseName, let impact):
                    DeleteRecordingDialog(
                        recording: recording,
                        courseName: courseName,
                        impact: impact,
                        delete: {
                            sheet.wrappedValue = nil
                            guard let library else { return }
                            Task {
                                await LibraryEditing.delete(recording, in: library)
                                await reload()
                            }
                        },
                        cancel: { sheet.wrappedValue = nil }
                    )

                case .editCourse(let course, let termIDs):
                    CourseDialog(
                        terms: terms,
                        draft: CourseDraft(editing: course, termIDs: termIDs),
                        confirm: { draft in
                            sheet.wrappedValue = nil
                            guard let library else { return }
                            Task {
                                await LibraryEditing.update(draft, in: library)
                                await reload()
                            }
                        },
                        cancel: { sheet.wrappedValue = nil }
                    )
                }
            }
        }
    }
}
