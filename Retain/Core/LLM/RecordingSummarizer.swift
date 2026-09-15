import Foundation

/// Runs the map over a recording and the reduce after it.
///
/// The shape is the one the brief describes and nothing more: every closed
/// block goes to the **small** model on its own while the recording is still
/// running, and one reduce afterwards sees every card plus the transcript of
/// record. Which model the reduce gets is not decided here — it is handed in,
/// because the answer depends on whether the Mac is plugged in, and
/// `ModelSizeDecision` is where that is written down.
///
/// **Nothing here re-summarises on its own.** Every call is something the user
/// or the session asked for, and there is no retry loop that quietly rewrites
/// notes in the background. The user can highlight passages of the finished
/// notes, and a regenerated summary invalidates the highlights sitting in it;
/// that is a decision for whoever is holding the recording, not something this
/// type may take by itself.
///
/// An actor, so a block that closes while the previous one is still being
/// summarised queues rather than racing it. Two three-minute summaries running
/// at once on a laptop finish no sooner and cost more.
actor RecordingSummarizer {

    /// Which model answers at which size.
    ///
    /// Two identifiers, not one: the settings pane picks both, because the
    /// point of the whole arrangement is that they are different models.
    nonisolated struct Configuration: Hashable, Sendable {
        var smallModel: String
        var largeModel: String

        func model(for size: ModelSize) -> String {
            switch size {
            case .small: smallModel
            case .large: largeModel
            }
        }
    }

    private let backend: any SummarizationBackend
    private let configuration: Configuration

    init(backend: any SummarizationBackend, configuration: Configuration) {
        self.backend = backend
        self.configuration = configuration
    }

    // MARK: - Map

    /// Summarises one closed block into the card the design draws.
    ///
    /// Always the small model, on mains or on battery. A block has to be
    /// summarised while the recording is running or the card is pointless, and
    /// the large model is not fast enough for that on a laptop even when there
    /// is power to spare.
    func summarise(_ block: TranscriptBlock) async throws -> NoteBlock {
        let reply = try await backend.structuredReply(
            to: NoteReduction.blockPrompt(for: block),
            model: configuration.smallModel,
            schema: NoteReduction.blockSchema,
            as: NoteReduction.BlockAnswer.self
        )
        return NoteReduction.noteBlock(from: reply.answer, for: block)
    }

    // MARK: - Reduce

    /// Writes the final notes.
    ///
    /// - Parameters:
    ///   - notes: the cards written while the recording ran.
    ///   - transcript: the batch transcript. The record, never the live pass.
    ///   - markers: every `⌘⇧M`, which the notes draw and the chapters flag.
    ///   - size: from `ModelSizeDecision`. Hard rule 7 lives there, not here.
    func reduce(
        notes: [NoteBlock],
        transcript: [TranscriptLine],
        markers: [RecordingMarker] = [],
        using size: ModelSize
    ) async throws -> RecordingNotes {
        let model = configuration.model(for: size)
        let conversation = NoteReduction.reducePrompt(notes: notes, transcript: transcript)

        try await checkItFits(conversation, model: model)

        let reply = try await backend.structuredReply(
            to: conversation,
            model: model,
            schema: NoteReduction.notesSchema,
            as: NoteReduction.NotesAnswer.self
        )

        return NoteReduction.notes(from: reply.answer, markers: markers)
    }

    /// Refuses a reduce that cannot fit before spending minutes on it.
    ///
    /// `contextOverflowPolicy` is `stopAtLimit`, so an over-long prompt would
    /// be reported rather than silently halved — but it would be reported after
    /// the large model had already run. Asking the server what context the
    /// model was actually loaded with costs one GET and turns that into a
    /// message the user can act on: load the model with a larger context.
    ///
    /// A server that does not say is not second-guessed. The check is skipped
    /// and the stop reason catches an overflow afterwards.
    private func checkItFits(_ conversation: ChatConversation, model: String) async throws {
        guard let contextLength = try? await backend.loadedContextLength(of: model) else { return }
        guard contextLength > 0 else { return }
        guard !TokenBudget.fits(conversation, in: contextLength) else { return }

        throw SummarizationError.contextTooSmall(
            needed: TokenBudget.estimatedTokens(in: conversation),
            available: TokenBudget.promptAllowance(of: contextLength)
        )
    }
}
