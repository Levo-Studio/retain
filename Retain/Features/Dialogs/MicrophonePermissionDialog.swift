import SwiftUI

/// The dialog that comes before the system's own.
///
/// macOS shows its permission sheet once and never again: a user who says no
/// there has to be sent to System Settings afterwards. So Retain says what the
/// recording is for first, and only then asks — which is also why "Later" is a
/// real answer here and not a way of refusing.
struct MicrophonePermissionDialog: View {

    let allow: () -> Void
    let later: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "Microphone", comment: "Settings section heading and sidebar row, and the label above the permission dialog title"),
            title: String(
                localized: "Retain needs access to your microphone",
                comment: "Microphone permission dialog title"
            ),
            message: {
                Text(
                    "The recording is processed only on this Mac. Nothing is uploaded, and only what you keep is stored.",
                    comment: "Microphone permission dialog body"
                )
            },
            footer: {
                DialogButtons(
                    cancelTitle: String(localized: "Later", comment: "Microphone permission dialog button that postpones the ask"),
                    confirmTitle: String(localized: "Allow access", comment: "Button that raises the microphone permission dialog"),
                    cancel: later,
                    confirm: allow
                )
            }
        )
    }
}
