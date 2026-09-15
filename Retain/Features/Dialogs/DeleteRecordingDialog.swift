import SwiftUI

/// "Delete recording": the second of the two places Retain destroys work.
///
/// It is built like `DeleteTermDialog` and for the same reasons — the body is
/// the count rather than a warning, and the destructive button carries no
/// keyboard shortcut, so Return cancels. What differs is what is at stake: by
/// the time a recording is in the library its audio is already gone, deleted as
/// soon as it was transcribed. The transcript **is** the lecture. There is no
/// recording to run the pass over again.
struct DeleteRecordingDialog: View {

    let recording: Recording

    /// The course's name, because "Delete recording" on its own does not say
    /// which lecture is about to go.
    let courseName: String

    /// Counted before the dialog opened — see
    /// `LibraryRepository.deletionImpact(ofRecording:)`.
    let impact: RecordingDeletion

    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "Recording", comment: "Popover header while a lecture is being recorded, and the title of the recording window"),
            labelDot: impact.isEmpty ? nil : RetainPalette.redError,
            labelInk: impact.isEmpty ? RetainPalette.inkLabel : RetainPalette.redInk,
            title: String(localized: "Delete recording", comment: "Delete-recording dialog title, and the button that confirms it"),
            message: { Text(Self.message(for: recording, courseName: courseName, impact: impact)) },
            footer: {
                Button(String(localized: "Cancel", comment: "Dialog button that closes without saving"), action: cancel)
                    .buttonStyle(RetainPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)

                Button(
                    String(localized: "Delete recording", comment: "Delete-recording dialog title, and the button that confirms it"),
                    action: delete
                )
                .buttonStyle(
                    RetainSecondaryButtonStyle(
                        ink: RetainPalette.redInk,
                        border: RetainPalette.redBorderSwatch
                    )
                )
                // Deleting is never the default action and has no shortcut of
                // any kind. It is reached by pointing at it.
                .disabled(impact.isRecording)
            }
        )
    }

    // MARK: - What it says

    static func message(
        for recording: Recording,
        courseName: String,
        impact: RecordingDeletion
    ) -> AttributedString {
        let name = Self.name(of: recording, courseName: courseName)
        var text = AttributedString(sentences(name: name, impact: impact))
        if let range = text.range(of: name) {
            text[range].foregroundColor = RetainPalette.inkPrimary
        }
        return text
    }

    /// How the lecture is named in the sentence: the course and when it was,
    /// which is how every other surface in Retain names one.
    static func name(of recording: Recording, courseName: String) -> String {
        DetailCopy.joined(courseName, RecordingPresentation.started(of: recording))
    }

    static func sentences(name: String, impact: RecordingDeletion) -> String {
        if impact.isRecording {
            return String(
                localized: "\(name) is being recorded right now. Stop it first; a recording cannot be deleted while the microphone is open.",
                comment: "Delete-recording dialog body when the lecture is still being recorded"
            )
        }

        guard !impact.isEmpty else {
            return String(
                localized: "Nothing was written down for \(name). Deleting it removes the row and nothing else.",
                comment: "Delete-recording dialog body for a recording that holds nothing"
            )
        }

        var parts = [String(
            localized: "\(name) holds \(impact.transcriptLines) lines of transcript, \(impact.noteBlocks) note blocks and \(impact.annotations) annotations.",
            comment: "Delete-recording dialog body counting what would be lost"
        )]

        // The sentence that matters, and the reason this dialog is not the same
        // as deleting anything else: there is no audio left to run the pass
        // over again. Said plainly, and only when it is true.
        if impact.hasAudio {
            parts.append(String(
                localized: "The audio has not been transcribed yet and goes with it.",
                comment: "Delete-recording dialog sentence for a recording whose audio is still on disk"
            ))
        } else {
            parts.append(String(
                localized: "The audio was deleted when the lecture was transcribed, so this is the only copy.",
                comment: "Delete-recording dialog sentence for a recording whose audio is already gone"
            ))
        }

        parts.append(String(
            localized: "This cannot be undone.",
            comment: "Closing sentence of the delete-term dialog body"
        ))

        return parts.joined(separator: " ")
    }
}
