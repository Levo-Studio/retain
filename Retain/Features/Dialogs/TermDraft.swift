import Foundation

// MARK: - A month

/// The period a term covers is drawn at **month granularity** — "Oct 2025",
/// "Mar 2026" — and never as a day.
///
/// `Term.startsOn` stores an instant, so a picked month is normalised to the
/// first moment of it. Doing that in one place is what keeps two terms picked
/// in two different ways from sorting against each other by the day somebody
/// happened to open the dialog.
nonisolated enum TermMonth {

    static func normalised(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// "Oct 2025", as the export draws it.
    static func label(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).year())
    }

    /// What a month field says when it has been left empty, and what the entry
    /// that empties it again is called.
    ///
    /// The export draws both fields filled and offers no way to clear one,
    /// because it was drawn when a period was required. It is not: a term with
    /// no period is a term that works, so each field has to be able to say it
    /// has nothing — in placeholder ink, the same way every other empty field
    /// in the app says it.
    static var noMonth: String {
        String(localized: "No month",
               comment: "A month field of a term's period that has been left empty, and the menu entry that empties it")
    }

    /// The months a picker offers around a date.
    ///
    /// Not drawn: the export shows two filled-in fields and no open menu. The
    /// range is two years back and three forward, which covers a school career
    /// somebody is recording and stays short enough to be one menu.
    static func choices(around date: Date, calendar: Calendar = .current) -> [Date] {
        let anchor = normalised(date, calendar: calendar)
        return (-24...36).compactMap { calendar.date(byAdding: .month, value: $0, to: anchor) }
    }
}

// MARK: - The draft

/// What the "Name term" dialog holds while it is open.
///
/// A value rather than four `@State` properties, so that "is this saveable" and
/// "what does this become" are answerable without a view.
nonisolated struct TermDraft: Equatable, Sendable {

    var title: String
    var kind: TermKind

    /// Either endpoint may be left empty, and so may both. The period is a
    /// caption and nothing computes with it, so a term somebody cannot date is
    /// a term that still works — see `Term.startsOn`.
    var startsOn: Date?
    var endsOn: Date?

    var isCurrent: Bool

    /// The term being edited, or `nil` for a new one.
    var id: Int64?

    init(
        id: Int64? = nil,
        title: String = "",
        kind: TermKind = .halfYear,
        startsOn: Date? = nil,
        endsOn: Date? = nil,
        isCurrent: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.startsOn = startsOn.map { TermMonth.normalised($0) }
        self.endsOn = endsOn.map { TermMonth.normalised($0) }
        self.isCurrent = isCurrent
    }

    init(_ term: Term) {
        self.init(
            id: term.id,
            title: term.title,
            kind: term.kind,
            startsOn: term.startsOn,
            endsOn: term.endsOn,
            isCurrent: term.isCurrent
        )
    }

    /// A term needs a name. Nothing else is required: the title is free text
    /// and there is no format to hold it to.
    ///
    /// The period is optional at both ends, so the only thing left to check is
    /// that a period somebody *did* give both ends of runs forwards. One
    /// endpoint on its own cannot be backwards, and neither cannot be anything.
    var isSaveable: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let startsOn, let endsOn else { return true }
        return startsOn <= endsOn
    }

    /// The row, with `isCurrent` **cleared**.
    ///
    /// The schema carries a partial unique index on `isCurrent`, so writing a
    /// second current term fails outright rather than quietly winning. Making a
    /// term current is therefore `LibraryRepository.makeCurrent(_:)` and nothing
    /// else — one transaction that clears the old one and sets the new one —
    /// and the row this builds must not try to do it on the way past.
    func term() -> Term {
        Term(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            startsOn: startsOn.map { TermMonth.normalised($0) },
            endsOn: endsOn.map { TermMonth.normalised($0) },
            isCurrent: false
        )
    }
}

// MARK: - The one current term

/// Which term stops being the current one when this draft becomes it.
///
/// At most one term is current and the database enforces it. The dialog says so
/// before the switch is thrown rather than letting the change happen silently:
/// "current" decides what the library opens on, and somebody who moves it
/// should see what they moved it off.
nonisolated enum CurrentTerm {

    /// The term that would be displaced, or `nil` when nothing would be.
    static func displaced(by draft: TermDraft, among terms: [Term]) -> Term? {
        guard draft.isCurrent else { return nil }
        return terms.first { $0.isCurrent && $0.id != draft.id }
    }

    /// The sentence under the toggle when one would be.
    static func warning(displacing term: Term) -> String {
        String(localized: "\(term.title) stops being the current term.",
               comment: "Note in the name-term dialog when switching the current term away from another one")
    }

    /// The sentence the export draws, for when nothing is displaced.
    static var caption: String {
        String(localized: "shown as selected at the top",
               comment: "Caption beside the current-term toggle")
    }
}

// MARK: - Term kind

nonisolated extension TermKind {

    /// The two the user picks between. **Nothing in the export draws this** —
    /// it is the one place the written brief goes past the design — so the
    /// words are invented and the control is the segment the export already
    /// uses elsewhere.
    var title: String {
        switch self {
        case .halfYear:
            String(localized: "Half-year", comment: "One of the two kinds a term can be")
        case .semester:
            String(localized: "Semester", comment: "One of the two kinds a term can be")
        }
    }
}
