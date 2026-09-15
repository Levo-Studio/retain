import Foundation

/// One turn of a chat prompt.
nonisolated struct ChatMessage: Hashable, Sendable {

    enum Role: String, Hashable, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String

    static func system(_ content: String) -> ChatMessage { ChatMessage(role: .system, content: content) }
    static func user(_ content: String) -> ChatMessage { ChatMessage(role: .user, content: content) }
}

/// A whole prompt, ready to send.
///
/// A plain value with no reference to a backend, so the pipeline can build one
/// and a test can read it back without a server anywhere near it.
nonisolated struct ChatConversation: Hashable, Sendable {

    var messages: [ChatMessage]

    init(_ messages: [ChatMessage]) {
        self.messages = messages
    }
}

// MARK: - The fallback ladder

/// How strictly the model was asked to answer in JSON.
///
/// Hard rule 12: **all three rungs are real.** A 3–8B model does not hold a
/// schema contract reliably — some builds reject `json_schema` outright, some
/// accept it and ignore it, some honour it until the answer gets long — so the
/// client walks down the ladder rather than treating the first refusal as a
/// failure. Which rung produced an answer is carried back with it, because a
/// backend that quietly needs the bottom rung every time is a configuration
/// problem worth seeing.
nonisolated enum StructuredOutputMode: String, Hashable, Sendable, CaseIterable {

    /// `response_format: json_schema` with `strict: true`. The server
    /// constrains decoding, and the answer is valid by construction.
    case jsonSchema

    /// `response_format: json_object`. The answer is JSON but the shape is on
    /// the model. Enough for an answer with four fields.
    case jsonObject

    /// No `response_format` at all, with the schema described in the prompt and
    /// the answer dug out of whatever came back.
    case freeText

    /// Tried in this order, always.
    static let ladder: [StructuredOutputMode] = [.jsonSchema, .jsonObject, .freeText]
}

/// Why the model stopped writing.
///
/// Hard rule 13 exists because of the second group. `contextOverflowPolicy` is
/// `stopAtLimit` rather than `truncateMiddle` precisely so that running out of
/// room is reported instead of hidden, and that report is worth nothing unless
/// somebody reads it — so every reply goes through here and a truncating stop
/// is an error, not a shorter answer.
nonisolated enum StopReason: Hashable, Sendable {

    // Finished on its own.
    case endOfSequence
    case stopString
    case toolCalls

    // Stopped short.
    case maxPredictedTokens
    case contextLengthReached
    case modelUnloaded
    case userStopped
    case failed

    /// A value this version of LM Studio has and Retain does not know.
    /// Treated as finished: inventing a failure out of an unknown string would
    /// throw away answers that are fine.
    case unknown(String)

    var isComplete: Bool {
        switch self {
        case .maxPredictedTokens, .contextLengthReached, .modelUnloaded, .userStopped, .failed:
            false
        case .endOfSequence, .stopString, .toolCalls, .unknown:
            true
        }
    }

    /// Maps the `stop_reason` string that `/api/v0/` returns.
    ///
    /// `/v1/` has no such field — it has `finish_reason`, which says `"length"`
    /// for both "hit the token cap" and "ran out of context" and cannot tell
    /// them apart. That difference is the whole reason Retain is on `/api/v0/`.
    static func parse(_ raw: String?) -> StopReason {
        switch raw {
        case nil: .unknown("")
        case "eosFound": .endOfSequence
        case "stopStringFound": .stopString
        case "toolCalls": .toolCalls
        case "maxPredictedTokensReached": .maxPredictedTokens
        case "contextLengthReached": .contextLengthReached
        case "modelUnloaded": .modelUnloaded
        case "userStopped": .userStopped
        case "failed": .failed
        case .some(let value): .unknown(value)
        }
    }

    /// The fallback for a reply that carries only OpenAI's `finish_reason`.
    /// Coarser on purpose — see `parse`.
    static func parseFinishReason(_ raw: String?) -> StopReason {
        switch raw {
        case "stop": .endOfSequence
        case "length": .maxPredictedTokens
        case "tool_calls": .toolCalls
        case nil: .unknown("")
        case .some(let value): .unknown(value)
        }
    }
}

/// A decoded answer plus what the server said about how it was produced.
nonisolated struct StructuredReply<Answer: Sendable>: Sendable {

    let answer: Answer

    /// Which rung of the ladder produced it.
    let mode: StructuredOutputMode

    let stopReason: StopReason

    /// `loaded_context_length` from `/api/v0/`, when the server reported it.
    let contextLength: Int?
}

// MARK: - Server description

/// A model the server offers.
nonisolated struct LanguageModelDescriptor: Hashable, Sendable, Identifiable {

    /// Whether the server has the model in memory.
    ///
    /// LM Studio lists every model it knows about, loaded or not, and the first
    /// request to an unloaded one waits for it to be read off disk — twenty
    /// seconds for a 20B model, during which Retain looked like it was doing
    /// nothing. Knowing which state a model is in is what lets that be said out
    /// loud instead.
    enum State: String, Hashable, Sendable {
        case loaded
        case notLoaded = "not-loaded"
        case loading

        /// Anything the server says that is none of the above. Reported as
        /// not-loaded rather than as an error: a state Retain does not know is
        /// not a reason to refuse to talk to the model.
        static func from(_ raw: String?) -> State {
            guard let raw else { return .notLoaded }
            return State(rawValue: raw) ?? .notLoaded
        }
    }

    /// What the request has to say in its `model` field.
    let id: String

    /// `nil` when the server did not say.
    let contextLength: Int?

    var state: State = .notLoaded
}

/// The answer to "Test connection".
///
/// The design draws it as "Connected · 3 models loaded · answered in 240 ms",
/// so both numbers are here and neither is computed in a view.
nonisolated struct ConnectionReport: Hashable, Sendable {
    let modelCount: Int
    let latency: TimeInterval
}

// MARK: - Errors

nonisolated enum SummarizationError: Error, Equatable, LocalizedError {

    /// The configured base URL points somewhere other than this Mac.
    ///
    /// Hard rule 9. This is not a setting with a sensible non-local value that
    /// Retain happens not to support — there is no network code in Retain
    /// beyond `localhost`, and a request that would leave the machine is
    /// refused before a socket is opened rather than after.
    case notLocalhost

    /// Nothing answered at the configured address.
    case unreachable

    case httpStatus(Int)

    /// The server refused the request for want of a token.
    ///
    /// Its own case rather than an `httpStatus(401)` because the remedy is
    /// specific and the generic message hides it completely: "LM Studio
    /// answered with an error. (401)" is true and sends the reader looking at
    /// the address and the endpoint, which is where this was in fact looked
    /// for. LM Studio can be told to require a token, and then it wants one on
    /// every request including the model list.
    case unauthorized

    /// A reply with no choices in it.
    case emptyReply

    /// The model stopped short. Carries the reason so the message can say
    /// whether it ran out of context or out of tokens.
    case truncated(StopReason)

    /// The prompt cannot fit the model's context, measured before sending.
    case contextTooSmall(needed: Int, available: Int)

    /// All three rungs of the ladder came back with something that is not an
    /// answer.
    case unreadableAnswer

    case noModelSelected

    /// A question was asked before there was anything to answer from.
    ///
    /// Carries the state rather than a flat "not available", because the
    /// interface draws the two reasons differently: a recording that is still
    /// running, and one whose summary has not landed yet.
    case chatNotReady(ChatAvailability)

    var errorDescription: String? {
        switch self {
        case .notLocalhost:
            String(localized: "Retain only talks to a language model on this Mac.",
                   comment: "The configured LM Studio address is not on localhost")
        case .unreachable:
            String(localized: "LM Studio is not responding.",
                   comment: "No server answered at the configured address")
        case .unauthorized:
            String(localized: "LM Studio requires an API token. Put it in the API key field above.",
                   comment: "The language model server refused the request for want of a token")
        case .httpStatus(let code):
            String(localized: "LM Studio answered with an error. (\(code))",
                   comment: "The language model server returned an HTTP error status")
        case .emptyReply:
            String(localized: "LM Studio returned an empty answer.",
                   comment: "The chat completion had no choices in it")
        case .truncated(.contextLengthReached):
            String(localized: "The model ran out of context before it finished the notes.",
                   comment: "The prompt plus the answer exceeded the loaded context length")
        case .truncated:
            String(localized: "The model stopped before it finished the notes.",
                   comment: "The model stopped for a reason other than finishing")
        case .contextTooSmall(let needed, let available):
            String(localized: "This recording needs about \(needed) tokens and the model has room for \(available). Load the model with a larger context.",
                   comment: "The prompt is too large for the loaded context length, measured before sending")
        case .unreadableAnswer:
            String(localized: "The model did not answer in a shape Retain could read.",
                   comment: "None of the three structured-output attempts produced a usable answer")
        case .noModelSelected:
            String(localized: "No language model is selected.",
                   comment: "Summarizing was asked for before a model was chosen in settings")
        case .chatNotReady(.stillRecording):
            String(localized: "Questions can be asked once the recording has stopped.",
                   comment: "The chat was used while the recording was still running")
        case .chatNotReady:
            String(localized: "Questions can be asked once the summary is finished.",
                   comment: "The chat was used before the notes had been written")
        }
    }
}

// MARK: - The backend

/// What the rest of Retain knows about a language model.
///
/// A protocol rather than the LM Studio client directly, so that everything
/// above it — the map over blocks, the reduce, the summariser — can be tested
/// against a backend that answers from a recorded reply. The alternative is
/// testing the pipeline against a live server, which means the pipeline is only
/// tested on a machine that happens to have one running.
nonisolated protocol SummarizationBackend: Sendable {

    /// Every model the server offers, for the settings picker.
    func availableModels() async throws -> [LanguageModelDescriptor]

    /// The context window the named model is currently loaded with, or `nil`
    /// when the server did not say or the model is not loaded.
    ///
    /// The number matters because it is the one the prompt is measured against
    /// before a reduce is sent. A model's advertised context and the context it
    /// was actually loaded with are routinely different — LM Studio loads a
    /// 128k model at 4k by default — and it is the loaded one that decides
    /// whether a recording fits.
    func loadedContextLength(of model: String) async throws -> Int?

    /// Asks the server to read the model into memory, and returns once it is
    /// there.
    ///
    /// LM Studio loads on first use, so this is a request with nothing in it —
    /// the cheapest thing that makes the server do the work. It is a separate
    /// verb because the waiting is the point: a summary that takes twenty
    /// seconds because the model was cold is indistinguishable from one that
    /// is not coming, and only Retain can tell the user which it is.
    func load(_ model: String) async throws

    func checkConnection() async throws -> ConnectionReport

    /// Sends `conversation` and decodes the answer, walking the fallback ladder.
    ///
    /// Throws `SummarizationError.truncated` when the model stopped short. It
    /// is not returned as a shorter answer: half a recording summarised as if it
    /// were the whole recording is exactly the failure hard rule 13 is about.
    func structuredReply<Answer: Decodable & Sendable>(
        to conversation: ChatConversation,
        model: String,
        schema: SchemaDescription,
        as answer: Answer.Type
    ) async throws -> StructuredReply<Answer>
}
