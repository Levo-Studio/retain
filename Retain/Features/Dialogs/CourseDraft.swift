import Foundation

/// What the "New course" dialog holds while it is open.
///
/// **There is no teacher field.** Board 05 draws a teacher in the course header
/// and no dialog anywhere offers a field for one; the owner settled it — there
/// is no teacher, and the segment is gone.
nonisolated struct CourseDraft: Equatable, Sendable {

    var name: String
    var termID: Int64?
    var color: CourseColor

    init(name: String = "", termID: Int64? = nil, color: CourseColor = .accent) {
        self.name = name
        self.termID = termID
        self.color = color
    }

    /// A course needs a name and a term to be in. A course that runs across two
    /// terms is two rows, one per term, which is what board 05 draws.
    var isSaveable: Bool {
        termID != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func course() -> Course? {
        guard let termID, isSaveable else { return nil }
        return Course(
            termID: termID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color
        )
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
