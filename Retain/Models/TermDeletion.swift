import Foundation

/// What deleting a term costs, counted before anyone is asked to agree to it.
///
/// Retain has exactly one action that destroys work a person cannot get back: a
/// term's recordings cascade with it, and a recording is a lecture somebody sat
/// through and can never sit through again. So the confirmation does not ask
/// "are you sure" — it says what goes, with numbers, and lets the reader decide
/// against it on the facts.
nonisolated struct TermDeletion: Equatable, Sendable {

    /// Recordings made in this term. Each takes its transcript, its notes, its
    /// annotations and its highlights with it.
    let recordings: Int

    /// Courses that run in this term and in no other, by name.
    ///
    /// A course that also runs elsewhere survives with that term's recordings
    /// untouched — which is the whole point of one course across several terms.
    /// One that ran only here has nowhere left to be.
    let coursesLost: [String]

    /// Nothing recorded and no course stranded: deleting it costs the title and
    /// nothing else, and the confirmation can say so plainly.
    var isEmpty: Bool { recordings == 0 && coursesLost.isEmpty }
}
