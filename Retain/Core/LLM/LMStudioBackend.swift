import Foundation

/// Talks to LM Studio on this Mac.
///
/// Three things about it are not style choices:
///
/// - **Completions go to `/api/v0/chat/completions`**, not `/v1/`. See
///   `LMStudioEndpoint`.
/// - **`contextOverflowPolicy` is `stopAtLimit`** and every reply's stop reason
///   is read. Hard rule 13.
/// - **The fallback ladder is walked, not assumed.** Hard rule 12.
///
/// And one thing that is a rule of its own: **nothing here logs.** Not the
/// prompt, not the answer, not the key, not the URL, not at `debug` level, not
/// behind a flag. The prompt is a transcript of somebody's recording and the
/// answer is their notes; `os_log` writes to a system-wide store that other
/// processes can read, and a recording that leaves the app through a log has left
/// the app.
nonisolated final class LMStudioBackend: SummarizationBackend {

    private let endpoint: LMStudioEndpoint
    private let transport: any HTTPTransport

    /// Read on every request rather than held.
    ///
    /// The key is a secret with a lifetime of one request. Keeping it in a
    /// property would put it in every memory dump for as long as the app is
    /// running, to save a keychain read that costs microseconds.
    private let apiKey: @Sendable () -> String?

    init(
        endpoint: LMStudioEndpoint,
        transport: any HTTPTransport = URLSessionTransport(),
        apiKey: @escaping @Sendable () -> String? = { try? RetainKeychain.languageModelAPIKey.read() }
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.apiKey = apiKey
    }

    // MARK: - Models

    func availableModels() async throws -> [LanguageModelDescriptor] {
        let (data, response) = try await transport.send(get(endpoint.models))
        try check(response)

        let list = try decoder.decode(OpenAIModelList.self, from: data)
        return list.data.map { LanguageModelDescriptor(id: $0.id, contextLength: nil) }
    }

    func loadedContextLength(of model: String) async throws -> Int? {
        let (data, response) = try await transport.send(get(endpoint.model(model)))

        // A model the server does not know about is not an error worth
        // stopping for: the pre-flight simply does not happen and the stop
        // reason catches an overflow afterwards.
        guard response.statusCode != 404 else { return nil }
        try check(response)

        let detail = try decoder.decode(NativeModel.self, from: data)
        return detail.loadedContextLength
    }

    func checkConnection() async throws -> ConnectionReport {
        let started = Date()
        let models = try await availableModels()
        return ConnectionReport(modelCount: models.count, latency: Date().timeIntervalSince(started))
    }

    // MARK: - Completions

    func structuredReply<Answer: Decodable & Sendable>(
        to conversation: ChatConversation,
        model: String,
        schema: SchemaDescription,
        as answer: Answer.Type
    ) async throws -> StructuredReply<Answer> {
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SummarizationError.noModelSelected
        }

        var lastFailure: SummarizationError = .unreadableAnswer

        for mode in StructuredOutputMode.ladder {
            do {
                return try await attempt(mode, conversation, model, schema, answer)
            } catch let error as SummarizationError {
                guard Self.descends(on: error) else { throw error }
                lastFailure = error
            }
        }

        throw lastFailure
    }

    /// One rung.
    private func attempt<Answer: Decodable & Sendable>(
        _ mode: StructuredOutputMode,
        _ conversation: ChatConversation,
        _ model: String,
        _ schema: SchemaDescription,
        _ answer: Answer.Type
    ) async throws -> StructuredReply<Answer> {
        var messages = conversation.messages
        if let instruction = Self.formatInstruction(for: mode, schema: schema) {
            messages.append(.system(instruction))
        }

        var request = URLRequest(url: endpoint.chatCompletions)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.requestBody(model: model, messages: messages, mode: mode, schema: schema).data
        authorise(&request)

        let (data, response) = try await transport.send(request)
        try check(response)

        let completion: CompletionResponse
        do {
            completion = try decoder.decode(CompletionResponse.self, from: data)
        } catch {
            // A reply whose envelope does not parse is not a rung failure, but
            // it is indistinguishable from one from here, and descending costs
            // two more requests against a server that is already answering
            // nonsense. Better that than a crash mid-recording.
            throw SummarizationError.unreadableAnswer
        }

        guard let content = completion.choices.first?.message?.content, !content.isEmpty else {
            throw SummarizationError.emptyReply
        }

        // Read before the answer is decoded, not after. A truncated reply often
        // still parses — the model was three bullets into a list — and an
        // answer that parses is an answer nobody looks at twice.
        let stopReason = completion.stopReason
        guard stopReason.isComplete else {
            throw SummarizationError.truncated(stopReason)
        }

        let decoded: Answer
        do {
            decoded = try StructuredJSON.decode(Answer.self, from: content)
        } catch {
            throw SummarizationError.unreadableAnswer
        }

        return StructuredReply(
            answer: decoded,
            mode: mode,
            stopReason: stopReason,
            contextLength: completion.modelInfo?.loadedContextLength
        )
    }

    /// Whether a failure means "try the next rung" or "stop".
    ///
    /// Only two do. A server that rejects the request outright is a server that
    /// does not support this rung — LM Studio answers 400 for a
    /// `json_schema` an engine cannot compile — and an answer that is not the
    /// expected shape is what the ladder exists for. Everything else, above all
    /// a truncating stop reason, is a real answer about a real problem, and
    /// re-asking with a looser format would spend another two minutes of a
    /// large model to be told the same thing.
    private static func descends(on error: SummarizationError) -> Bool {
        switch error {
        case .unreadableAnswer, .emptyReply:
            true
        case .httpStatus(let code):
            code == 400 || code == 415 || code == 422 || code == 500
        default:
            false
        }
    }

    // MARK: - Request shape

    /// Low, not zero.
    ///
    /// Zero makes a small model repeat itself across blocks — every card opens
    /// with the same clause — because nothing breaks the tie between two
    /// equally likely openings. Low enough that the notes stay close to what
    /// was actually said.
    static let temperature = 0.2

    /// Hard rule 13. `truncateMiddle`, which is the server's default, drops the
    /// middle of an over-long prompt and answers as if nothing had happened —
    /// half a recording summarised, with no sign that half of it is missing.
    ///
    /// The field is sent on every request. If a build of LM Studio ignores it,
    /// the stop reason above is the second line of defence, which is why both
    /// exist.
    static let contextOverflowPolicy = "stopAtLimit"

    /// What the lower two rungs put in front of the model instead of a schema.
    ///
    /// `json_object` mode requires the word "JSON" to appear in the prompt at
    /// all — servers reject the request otherwise — and free-text mode has
    /// nothing but this paragraph keeping the answer machine-readable, so the
    /// schema is spelled out in both.
    static func formatInstruction(for mode: StructuredOutputMode, schema: SchemaDescription) -> String? {
        guard mode != .jsonSchema else { return nil }

        return """
            Answer with a single JSON object and nothing else. No explanation before it, \
            no code fence around it, no comment inside it. It must match this JSON Schema:
            \(schema.schema.serialized)
            """
    }

    /// The completion request.
    ///
    /// Built as a `JSONValue` and serialised by hand rather than encoded from a
    /// `Codable` struct, because the schema's property order has to survive to
    /// the wire and `JSONEncoder` does not carry it — see `JSONValue`.
    static func requestBody(
        model: String,
        messages: [ChatMessage],
        mode: StructuredOutputMode,
        schema: SchemaDescription
    ) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("model", .string(model)),
            ("messages", .array(messages.map { message in
                .object([
                    ("role", .string(message.role.rawValue)),
                    ("content", .string(message.content)),
                ])
            })),
            ("temperature", .number(temperature)),
            // Retain reads the whole answer at once. There is no half-written
            // note to draw, so a stream would only add a parser to go wrong.
            ("stream", .boolean(false)),
            ("contextOverflowPolicy", .string(contextOverflowPolicy)),
        ]

        switch mode {
        case .jsonSchema:
            pairs.append(("response_format", .object([
                ("type", .string("json_schema")),
                ("json_schema", .object([
                    ("name", .string(schema.name)),
                    ("strict", .boolean(true)),
                    ("schema", schema.schema),
                ])),
            ])))
        case .jsonObject:
            pairs.append(("response_format", .object([("type", .string("json_object"))])))
        case .freeText:
            // No `response_format` at all: a server that does not understand
            // the field is likelier to reject the request than to ignore it.
            break
        }

        return .object(pairs)
    }

    // MARK: - Plumbing

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func get(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        authorise(&request)
        return request
    }

    private func authorise(_ request: inout URLRequest) {
        guard let key = apiKey(), !key.isEmpty else { return }
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }

    private func check(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            // 401 and 403 are the same thing to a reader — the server will not
            // talk to you without a token — and the remedy is one field in
            // Settings. Left as a bare status code, the message sends them
            // looking at the address and the endpoint instead.
            if response.statusCode == 401 || response.statusCode == 403 {
                throw SummarizationError.unauthorized
            }
            throw SummarizationError.httpStatus(response.statusCode)
        }
    }
}

// MARK: - Wire types

/// What `/api/v0/chat/completions` sends back.
///
/// Everything below `choices` is optional, including the two fields this route
/// was chosen for. A build that stops sending `stats.stop_reason` must not turn
/// every summary into a crash — it degrades to `finish_reason`, which cannot
/// tell "ran out of tokens" from "ran out of context" but can still tell both
/// from "finished".
private nonisolated struct CompletionResponse: Decodable {

    nonisolated struct Choice: Decodable {
        nonisolated struct Message: Decodable {
            let content: String?
        }

        let message: Message?
        let finishReason: String?
    }

    nonisolated struct Stats: Decodable {
        let stopReason: String?
    }

    nonisolated struct ModelInfo: Decodable {
        let loadedContextLength: Int?
    }

    let choices: [Choice]
    let stats: Stats?
    let modelInfo: ModelInfo?

    var stopReason: StopReason {
        if let reason = stats?.stopReason {
            return StopReason.parse(reason)
        }
        return StopReason.parseFinishReason(choices.first?.finishReason)
    }
}

private nonisolated struct OpenAIModelList: Decodable {

    nonisolated struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private nonisolated struct NativeModel: Decodable {
    let id: String
    let loadedContextLength: Int?
}
