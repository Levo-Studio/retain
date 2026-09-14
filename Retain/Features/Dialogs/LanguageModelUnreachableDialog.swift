import SwiftUI

/// "LM Studio is not responding".
///
/// The body says the recording keeps running and that summaries are caught up
/// once the connection is back, **and that has to be true** — the microphone
/// and the speech models are on this Mac and owe the language model nothing.
/// Whatever raises this dialog must not stop a recording; the blocks that could
/// not be summarised wait and are sent when a later attempt succeeds.
struct LanguageModelUnreachableDialog: View {

    /// The configured address, stripped of anything that could be a secret
    /// before it is drawn.
    let address: String

    let retry: () -> Void
    let openSettings: () -> Void

    var body: some View {
        RetainDialog(
            label: String(localized: "No connection", comment: "Uppercase label above the LM Studio failure dialog title"),
            labelDot: RetainPalette.redError,
            labelInk: RetainPalette.redInk,
            title: Self.title,
            message: { Text(Self.body(naming: BaseAddress.displayed(address))) },
            footer: {
                DialogButtons(
                    cancelTitle: String(localized: "Settings", comment: "Settings window title, and the button that opens it"),
                    confirmTitle: String(localized: "Try again", comment: "Button that retries the speech model download or the LM Studio connection"),
                    cancel: openSettings,
                    confirm: retry
                )
            }
        )
    }

    /// "LM Studio is not responding" — the sentence Retain already has for
    /// this, without the full stop a title does not take.
    ///
    /// Not a second string catalog entry, because it cannot be one: the
    /// project generates a Swift symbol per key, and two keys differing only in
    /// a full stop generate the same symbol and fail the build. Nor is that a
    /// reason to draw the stop — none of the four dialog titles on board 07
    /// ends in one.
    static var title: String {
        let sentence = SummarizationError.unreachable.errorDescription ?? ""
        return sentence.hasSuffix(".") ? String(sentence.dropLast()) : sentence
    }

    /// One sentence with the address set in primary ink, as the export draws
    /// it.
    ///
    /// One string catalog key rather than a sentence glued together around the
    /// address: a translator given "No server was reachable at " and ". The
    /// recording continues…" as two entries has been handed two fragments and
    /// no sentence. The ink is applied to the address's range afterwards.
    static func body(naming address: String) -> AttributedString {
        var text = AttributedString(
            String(
                localized: "No server was reachable at \(address). Recording continues; summaries are caught up once the connection is back.",
                comment: "LM Studio failure dialog body, naming the configured address"
            )
        )
        if let range = text.range(of: address) {
            text[range].foregroundColor = RetainPalette.inkPrimary
        }
        return text
    }
}
