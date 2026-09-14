import Foundation

/// The chat rail for one recording.
///
/// **One conversation per recording**, and no other scope. Not per course and
/// not global: board 04 says what it is for in the rail itself — "Fragen zu
/// dieser Stunde. Das Modell sieht Notizen und Transkript" — and a chat that
/// spanned a term would be answering from material the question was not about.
///
/// It is only usable once the recording has stopped **and** the summary has
/// finished, and that is a state the interface reads rather than an error it
/// discovers. The rail is on screen while the recording is still running.
actor RecordingChat {

    /// What the chat is asked against. Held rather than fetched, because the
    /// notes and the transcript are what make this conversation this
    /// conversation.
    nonisolated struct Material: Sendable {
        var notes: RecordingNotes?
        var transcript: [TranscriptLine]
        var isRecording: Bool

        init(notes: RecordingNotes?, transcript: [TranscriptLine], isRecording: Bool = false) {
            self.notes = notes
            self.transcript = transcript
            self.isRecording = isRecording
        }
    }

    private let backend: any SummarizationBackend
    private let model: String
    private var material: Material

    /// The rail, oldest first.
    private(set) var turns: [ChatTurn] = []

    init(backend: any SummarizationBackend, model: String, material: Material) {
        self.backend = backend
        self.model = model
        self.material = material
    }

    /// Whether a question can be asked, and if not, why not.
    var availability: ChatAvailability {
        ChatAvailability.of(isRecording: material.isRecording, hasNotes: material.notes != nil)
    }

    /// Called when the recording stops and again when the summary lands.
    func update(_ material: Material) {
        self.material = material
    }

    // MARK: - Asking

    /// Asks a question and appends both turns.
    ///
    /// The question is appended before the model is asked, so the rail draws it
    /// immediately and keeps it when the answer fails. A question that vanished
    /// because the server was down would have to be typed again.
    @discardableResult
    func ask(_ question: String) async throws -> ChatTurn {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { throw SummarizationError.emptyReply }
        guard availability == .ready, let notes = material.notes else {
            throw SummarizationError.chatNotReady(availability)
        }

        turns.append(ChatTurn(author: .you, text: asked))

        let conversation = ChatAnswering.prompt(
            question: asked,
            notes: notes,
            transcript: material.transcript,
            history: turns.dropLast().map { $0 },
            transcriptBudget: await transcriptBudget(besides: asked, notes: notes)
        )

        let reply = try await backend.structuredReply(
            to: conversation,
            model: model,
            schema: ChatAnswering.schema,
            as: ChatAnswering.Answer.self
        )

        let answer = ChatAnswering.turn(
            from: reply.answer,
            blocks: notes.blocks,
            duration: material.transcript.last?.end
        )
        turns.append(answer)
        return answer
    }

    /// How many tokens are left for the transcript once everything else in the
    /// prompt has been counted.
    ///
    /// The notes, the question and the recent turns are all bounded and all
    /// have to be there. The transcript is the only part that can be ninety
    /// minutes long, so it is the only part that gets selected down — see
    /// `TranscriptRetrieval`, which picks the lines that match the question
    /// rather than the lines that happen to come first.
    private func transcriptBudget(besides question: String, notes: RecordingNotes) async -> Int {
        let contextLength = (try? await backend.loadedContextLength(of: model)) ?? nil
        let allowance = TokenBudget.promptAllowance(of: contextLength ?? Self.assumedContextLength)

        let fixed = ChatAnswering.prompt(
            question: question,
            notes: notes,
            transcript: [],
            history: turns.suffix(ChatAnswering.historyTurns).map { $0 },
            transcriptBudget: 0
        )

        return max(0, allowance - TokenBudget.estimatedTokens(in: fixed))
    }

    /// What to assume when the server will not say.
    ///
    /// LM Studio's own default. Assuming small is the safe direction: a
    /// transcript excerpt that is shorter than it needed to be gives a thinner
    /// answer, where one that is too long gives no answer at all.
    static let assumedContextLength = 4096
}
