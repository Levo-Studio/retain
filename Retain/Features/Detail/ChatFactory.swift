import Defaults
import Foundation

/// Builds the chat a recording is read with, out of what Settings holds.
///
/// **The chat was never built.** `RecordingChat` existed, its tests passed, the
/// rail drew a composer and a list of turns — and `RecordingChat(` appeared
/// nowhere in the app. `RecordingDetailModel` took one as an optional and every
/// caller left it `nil`, so asking a question did nothing at all, silently,
/// which is indistinguishable from a broken model or a broken server.
///
/// It is built per window and not held, for the same reason as
/// `SummarizerFactory`: the address and the model can change between one
/// recording and the next, and a chat made at launch would be answering to
/// whatever was true then.
///
/// `nil` when no model is chosen or the address is unusable. The rail already
/// draws an unavailable chat — that is `ChatAvailability` — so a window with no
/// model says so rather than offering a composer that cannot answer.
@MainActor
enum ChatFactory {

    static func make(material: RecordingChat.Material) -> RecordingChat? {
        let model = Defaults[.languageModelName]
        guard !model.isEmpty else { return nil }

        guard let endpoint = try? LMStudioEndpoint(address: Defaults[.languageModelAddress]) else {
            return nil
        }

        return RecordingChat(
            backend: LMStudioBackend(endpoint: endpoint),
            model: model,
            material: material
        )
    }
}
