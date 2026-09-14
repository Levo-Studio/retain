import Foundation

/// What the "New course" dialog holds while it is open.
///
/// **There is no teacher field.** Board 05 draws a teacher in the course header
/// and no dialog anywhere offers a field for one; the owner settled it — there
/// is no teacher, and the segment is gone.
nonisolated struct CourseDraft: Equatable, Sendable {

    var name: String

    /// Every term the course runs in, and there can be several: the same school
    /// subject runs in the winter half-year and in the summer one, and it is
    /// one course in both.
    var termIDs: Set<Int64>

    var color: CourseColor

    init(name: String = "", termIDs: Set<Int64> = [], color: CourseColor = .accent) {
        self.name = name
        self.termIDs = termIDs
        self.color = color
    }

    /// One term preselected — what the library sidebar and the General pane
    /// open the dialog with, since both already have a term chosen.
    init(name: String = "", termID: Int64?, color: CourseColor = .accent) {
        self.init(name: name, termIDs: termID.map { [$0] } ?? [], color: color)
    }

    /// A course needs a name and **at least one** term to run in.
    ///
    /// None is refused rather than allowed and hidden: every list of courses in
    /// the app is a term's list, so a course belonging to no term would be a
    /// row the user cannot see, cannot record into and cannot delete.
    var isSaveable: Bool {
        !termIDs.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The course row. Which terms it runs in is `termIDs`, written beside it —
    /// the row itself no longer carries a term.
    func course() -> Course? {
        guard isSaveable else { return nil }
        return Course(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color
        )
    }

    /// Ticks a term, or unticks it. The dialog's chips are a toggle each, and
    /// which way round they go is the draft's business rather than the view's.
    mutating func toggle(_ termID: Int64) {
        if termIDs.contains(termID) {
            termIDs.remove(termID)
        } else {
            termIDs.insert(termID)
        }
    }
}

// MARK: - The four colours

nonisolated extension CourseColor {

    /// Exactly four, in the order the dialog offers them.
    ///
    /// The order is the storage: `CourseColor` is written to the database as
    /// its index, so a colour is a position in this list and not a hex string
    /// that would go stale the moment `docs/design/` is refreshed.
    static var offered: [CourseColor] { allCases }

    /// What a swatch is called, for anybody reading the dialog rather than
    /// looking at it. The export names none of them; these are the README's own
    /// words for the four accent rows.
    var name: String {
        switch self {
        case .accent: String(localized: "Green", comment: "Name of the first course colour")
        case .blue: String(localized: "Blue", comment: "Name of the second course colour")
        case .amber: String(localized: "Amber", comment: "Name of the third course colour")
        case .purple: String(localized: "Purple", comment: "Name of the fourth course colour")
        }
    }
}
