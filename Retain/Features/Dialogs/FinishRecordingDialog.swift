import SwiftUI

/// "Finish recording": asked before the microphone closes.
///
/// Nothing on board 07 draws it. It is here because Finish is the one control
/// in Retain that cannot be undone by pressing it again — the microphone
/// closes, the batch pass starts, and a lecture that is still running is not
/// something the app can go back and record the rest of.
///
/// **What it says is what happens next**, not "are you sure". A reader
/// hesitating over this button is asking whether they are about to lose the
/// rest of the lesson, and the answer is the sentence: the recording stops, the
/// transcript is kept, and the model reads it afterwards.
struct FinishRecordingDialog: View {

    let elapsed: TimeInterval

    let finish: () -> Void
    let cancel: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "Recording", comment: "Field label for a recording, and the label above the finish-recording dialog title"),
            title: String(localized: "Finish recording", comment: "Finish-recording dialog title, and the button that confirms it"),
            message: { Text(verbatim: message) },
            footer: {
                DialogButtons(
                    cancelTitle: String(localized: "Keep recording", comment: "Finish-recording dialog button that closes it and leaves the microphone open"),
                    confirmTitle: String(localized: "Finish recording", comment: "Finish-recording dialog title, and the button that confirms it"),
                    cancel: cancel,
                    confirm: finish
                )
            }
        )
    }

    /// The length so far, because that is what somebody is weighing: a lecture
    /// four minutes in and one fifty minutes in are different decisions.
    ///
    /// Left out where it is not known — a window with no shell behind it — so
    /// the sentence never claims a lecture has just started when it has not.
    private var message: String {
        guard elapsed > 0 else {
            return String(
                localized: "The microphone closes. The transcript is kept, and the model reads it afterwards.",
                comment: "Finish-recording dialog body where the length of the recording is not known"
            )
        }
        return String(
            localized: "The microphone closes after \(RetainTimeFormat.clock(elapsed)). The transcript is kept, and the model reads it afterwards.",
            comment: "Finish-recording dialog body; the placeholder is how long the recording has run"
        )
    }
}
