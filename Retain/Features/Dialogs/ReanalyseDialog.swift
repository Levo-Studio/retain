import SwiftUI

/// "Write the notes again": the model reads the transcript once more and
/// replaces everything it wrote before.
///
/// Built like the two deletion dialogs, because it is one. Nothing about the
/// recording is lost — the transcript is the record and it is untouched — but
/// **the highlights are.** A highlight is a passage somebody marked by hand; it
/// hangs off the block it was marked in, and replacing the blocks takes it with
/// them. Nobody can mark a passage again in notes they no longer have.
///
/// So the dialog counts them, and says so only when there are any. A recording
/// with notes nobody has marked costs nothing to rewrite, and a warning that
/// fires every time is a warning nobody reads on the one occasion it matters.
struct ReanalyseDialog: View {

    let impact: ReanalysisImpact

    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "Notes", comment: "Uppercase label above the re-analysis dialog title"),
            labelDot: impact.highlights > 0 ? RetainPalette.amber : nil,
            title: String(localized: "Write the notes again",
                          comment: "Re-analysis dialog title, and the button that confirms it"),
            message: { Text(verbatim: Self.sentences(impact)) },
            footer: {
                DialogButtons(
                    cancelTitle: String(localized: "Cancel", comment: "Dialog button that closes without saving"),
                    confirmTitle: String(localized: "Write the notes again",
                                         comment: "Re-analysis dialog title, and the button that confirms it"),
                    isConfirmEnabled: impact.canRun,
                    cancel: cancel,
                    confirm: confirm
                )
            }
        )
    }

    // MARK: -

    static func sentences(_ impact: ReanalysisImpact) -> String {
        var parts = [String(
            localized: "The model reads the \(impact.transcriptLines) lines of transcript again and writes new notes.",
            comment: "Re-analysis dialog body naming how much transcript the model will read"
        )]

        if !impact.isFirstTime {
            parts.append(String(
                localized: "The \(impact.noteBlocks) note blocks it wrote before are replaced.",
                comment: "Re-analysis dialog sentence naming the note blocks that will be replaced"
            ))
        }

        // The one sentence this dialog exists for, and only when it is true.
        if impact.highlights > 0 {
            parts.append(String(
                localized: "The \(impact.highlights) passages you marked go with them, and cannot be marked again.",
                comment: "Re-analysis dialog sentence naming the highlights that will be lost"
            ))
        }

        parts.append(String(
            localized: "The transcript itself is not touched.",
            comment: "Re-analysis dialog closing sentence, saying what is safe"
        ))

        return parts.joined(separator: " ")
    }
}
