import SwiftUI

/// "Move recording": asked before a lecture changes hands.
///
/// Nothing on board 07 draws it, because nothing in the brief moved anything.
/// It is the same card as the other five, and it is here rather than the
/// picker simply writing because moving a recording is not a display setting:
/// it changes which course the lecture is filed under in the library, in the
/// search, and in every window that is open on either of them.
///
/// Both buttons are safe — nothing is destroyed either way — so unlike the
/// delete dialogs the confirming one is the default action, and Return takes
/// it. What it protects against is not a disaster, it is a misclick in a list
/// of courses that all start with the same two letters.
struct MoveRecordingDialog: View {

    let recording: Recording
    let from: Course?
    let to: Course

    let move: () -> Void
    let cancel: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "Course", comment: "Field label for a course, and the label above the move-recording dialog title"),
            title: String(localized: "Move recording", comment: "Move-recording dialog title, and the button that confirms it"),
            message: { Text(verbatim: message) },
            footer: {
                DialogButtons(
                    cancelTitle: String(localized: "Cancel", comment: "Dialog button that closes without saving"),
                    confirmTitle: String(localized: "Move recording",
                                         comment: "Move-recording dialog title, and the button that confirms it"),
                    cancel: cancel,
                    confirm: move
                )
            }
        )
    }

    /// One complete sentence per case, rather than fragments glued around two
    /// names — the same rule the delete dialogs are written under.
    private var message: String {
        let title = RecordingPresentation.title(of: recording)
        guard let from else {
            return String(
                localized: "\(title) moves to \(to.name). It stays in the same term.",
                comment: "Move-recording dialog body when the recording is not in a course yet"
            )
        }
        return String(
            localized: "\(title) moves from \(from.name) to \(to.name). It stays in the same term.",
            comment: "Move-recording dialog body: the recording, the course it is in, and the one it is going to"
        )
    }
}
