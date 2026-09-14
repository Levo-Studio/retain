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

    /// The term the course is created in. `nil` when none is selected, which
    /// the dialog itself then refuses.
    case newCourse(Int64?)

    var id: String {
        switch self {
        case .nameTerm(let term): "term-\(term?.id ?? 0)"
        case .newCourse(let termID): "course-\(termID ?? 0)"
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

    @discardableResult
    static func create(_ draft: CourseDraft, in library: LibraryRepository) async -> Course? {
        guard let course = draft.course() else { return nil }
        return try? await library.save(course)
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
                        draft: term.map(TermDraft.init) ?? TermDraft(startsOn: .now, endsOn: .now),
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
                    NewCourseDialog(
                        terms: terms,
                        draft: CourseDraft(termID: termID),
                        create: { draft in
                            sheet.wrappedValue = nil
                            guard let library else { return }
                            Task {
                                await LibraryEditing.create(draft, in: library)
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
