import Defaults
import Foundation

/// Builds the summariser a lecture runs with, out of what Settings holds.
///
/// It is rebuilt rather than kept because every part of it can change between
/// one lecture and the next: the user can point Retain at a different LM Studio
/// address, pick a different model, or start the server after Retain was
/// already open. A summariser held from launch would be answering to whatever
/// was true then.
///
/// Returns `nil` when the address is unusable or no model has been chosen. That
/// is not an error state — it is the ordinary condition of a fresh install
/// before anyone has been to Settings — and a lecture started in it records and
/// transcribes normally, with an empty notes column. What must not happen is
/// the recording refusing to start because a language model is not configured.
@MainActor
enum SummarizerFactory {

    static func make() -> RecordingSummarizer? {
        let model = Defaults[.languageModelName]
        guard !model.isEmpty else { return nil }

        guard let endpoint = try? LMStudioEndpoint(address: Defaults[.languageModelAddress]) else {
            return nil
        }

        // One model name for both sizes until Settings offers two. The design
        // draws a single picker, and the brief's split — the small model during
        // the lecture, the large one for the reduce afterwards — needs a second
        // field that board 06 does not have. Running both passes on the chosen
        // model is the honest reading of the interface as drawn; the moment a
        // second picker exists, this is where it arrives.
        return RecordingSummarizer(
            backend: LMStudioBackend(endpoint: endpoint),
            configuration: .init(smallModel: model, largeModel: model)
        )
    }
}
