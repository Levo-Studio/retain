import SwiftUI

/// "Delete term": the one dialog in Retain that is asked before work is
/// destroyed rather than before it is written.
///
/// Nothing on board 07 draws it, because nothing in the brief deleted anything.
/// It is built out of the same card as the other four, with two departures that
/// are both about the fact that a recording cannot be made again:
///
/// - **The body is the count, not a warning.** "Are you sure?" gives a reader
///   nothing to be sure about. The number of recordings and the names of the
///   courses that go with them are the only things that make the decision
///   answerable, so they are the sentence.
/// - **Return cancels.** The destructive button carries no keyboard shortcut at
///   all; the safe one is the default action and the escape. A dialog that
///   deletes a term because somebody was still typing is a bug with no repair.
struct DeleteTermDialog: View {

    let term: Term

    /// Counted before the dialog opened — see `LibraryRepository.deletionImpact`.
    let impact: TermDeletion

    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "Term", comment: "Field label for a term, and the label above the name-term dialog title"),
            labelDot: impact.isEmpty ? nil : RetainPalette.redError,
            labelInk: impact.isEmpty ? RetainPalette.inkLabel : RetainPalette.redInk,
            title: String(localized: "Delete term", comment: "Delete-term dialog title, and the button that confirms it"),
            message: { Text(Self.message(for: term, impact: impact)) },
            footer: {
                Button(String(localized: "Cancel", comment: "Dialog button that closes without saving"), action: cancel)
                    .buttonStyle(RetainPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)

                // No `.destructiveAction`, no `.defaultAction`, no shortcut of
                // any kind: this one is reached by pointing at it.
                Button(String(localized: "Delete term", comment: "Delete-term dialog title, and the button that confirms it"), action: delete)
                    .buttonStyle(
                        RetainSecondaryButtonStyle(
                            ink: RetainPalette.redInk,
                            border: RetainPalette.redBorderSwatch
                        )
                    )
            }
        )
    }

    // MARK: - What it says

    /// The whole body, assembled from whole sentences.
    ///
    /// Each case below is one string catalog key holding one complete sentence,
    /// rather than fragments glued together around a number. A translator given
    /// "holds" and "recordings" as separate entries has been handed no sentence
    /// to translate, and every language that inflects the noun after a count
    /// gets it wrong.
    static func message(for term: Term, impact: TermDeletion) -> AttributedString {
        var text = AttributedString(sentences(for: term, impact: impact))
        if let range = text.range(of: term.title) {
            text[range].foregroundColor = RetainPalette.inkPrimary
        }
        return text
    }

    static func sentences(for term: Term, impact: TermDeletion) -> String {
        let name = term.title

        guard !impact.isEmpty else {
            return String(
                localized: "Nothing was recorded in \(name). Deleting the term removes it and nothing else.",
                comment: "Delete-term dialog body for a term that holds nothing"
            )
        }

        var parts: [String] = []

        switch impact.recordings {
        case 0:
            break
        case 1:
            parts.append(String(
                localized: "\(name) holds one recording. Deleting the term deletes it, with its transcript, notes and annotations.",
                comment: "Delete-term dialog body naming the single recording that would be lost"
            ))
        default:
            parts.append(String(
                localized: "\(name) holds \(impact.recordings) recordings. Deleting the term deletes them all, with their transcripts, notes and annotations.",
                comment: "Delete-term dialog body naming how many recordings would be lost"
            ))
        }

        if let courses = coursesSentence(impact.coursesLost) {
            parts.append(courses)
        }

        parts.append(String(
            localized: "This cannot be undone.",
            comment: "Closing sentence of the delete-term dialog body"
        ))

        return parts.joined(separator: " ")
    }

    /// The courses that have nowhere left to be, named rather than counted.
    ///
    /// Named because the reader is the person who made them: "Informatik and
    /// Analysis are removed as well" is something they can disagree with, and
    /// "2 courses are removed as well" is not. A course that also runs in
    /// another term is not in this list and is not touched.
    private static func coursesSentence(_ names: [String]) -> String? {
        guard let first = names.first else { return nil }

        if names.count == 1 {
            return String(
                localized: "\(first) runs in no other term and is removed as well.",
                comment: "Delete-term dialog sentence naming the one course that would be removed with the term"
            )
        }

        let list = names.formatted(.list(type: .and))
        return String(
            localized: "\(list) run in no other term and are removed as well.",
            comment: "Delete-term dialog sentence naming the courses that would be removed with the term"
        )
    }
}
