import Foundation
import Testing

@testable import Retain

// MARK: - Recorded replies

/// A transport that answers from a queue of recorded replies and keeps every
/// request it was given.
///
/// The whole LM Studio client is tested through this and never against a
/// running server. A live server is not available on a build machine, and —
/// more to the point — a healthy one never produces the three answers that
/// matter here: prose instead of JSON, a rejected `json_schema`, and a stop
/// reason saying the model was cut off mid-sentence.
private nonisolated final class RecordedTransport: HTTPTransport, @unchecked Sendable {

    struct Reply {
        let status: Int
        let body: String

        init(_ status: Int = 200, _ body: String) {
            self.status = status
            self.body = body
        }
    }

    private let lock = NSLock()
    private var queued: [Reply]
    private var sent: [URLRequest] = []

    init(_ replies: [Reply]) {
        queued = replies
    }

    init(_ body: String) {
        queued = [Reply(200, body)]
    }

    var requests: [URLRequest] {
        lock.withLock { sent }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = try lock.withLock {
            sent.append(request)
            guard !queued.isEmpty else { throw SummarizationError.unreachable }
            return queued.removeFirst()
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(reply.body.utf8), response)
    }
}

/// The shapes LM Studio actually sends, trimmed of the fields Retain ignores.
private enum Recorded {

    /// `POST /api/v0/chat/completions`, a model that finished on its own.
    static func completion(
        content: String,
        stopReason: String? = "eosFound",
        finishReason: String = "stop",
        loadedContextLength: Int? = 8192
    ) -> String {
        let escaped = String(data: try! JSONEncoder().encode(content), encoding: .utf8)!
        let stats = stopReason.map { "\"stats\":{\"tokens_per_second\":41.8,\"stop_reason\":\"\($0)\"}," } ?? ""
        let info = loadedContextLength.map {
            "\"model_info\":{\"arch\":\"qwen2\",\"quant\":\"Q4_K_M\",\"format\":\"gguf\",\"context_length\":32768,\"loaded_context_length\":\($0)},"
        } ?? ""

        return """
            {"id":"chatcmpl-7f2","object":"chat.completion","created":1757800000,
             "model":"qwen2.5-7b-instruct",
             "choices":[{"index":0,"logprobs":null,"finish_reason":"\(finishReason)",
                         "message":{"role":"assistant","content":\(escaped)}}],
             "usage":{"prompt_tokens":1204,"completion_tokens":168,"total_tokens":1372},
             \(stats)\(info)
             "runtime":{"name":"llama.cpp-mac-arm64-apple-metal-advsimd","version":"1.52.0"}}
            """
    }

    /// `GET /v1/models`.
    static let models = """
        {"object":"list","data":[
          {"id":"qwen2.5-7b-instruct","object":"model","owned_by":"organization_owner"},
          {"id":"gemma-3-12b-it","object":"model","owned_by":"organization_owner"},
          {"id":"text-embedding-nomic-embed-text-v1.5","object":"model","owned_by":"organization_owner"}]}
        """

    /// `GET /api/v0/models/<id>`, loaded.
    static let loadedModel = """
        {"id":"qwen2.5-7b-instruct","object":"model","type":"llm","publisher":"lmstudio-community",
         "arch":"qwen2","quantization":"Q4_K_M","state":"loaded",
         "max_context_length":32768,"loaded_context_length":4096}
        """

    /// `GET /api/v0/models/<id>`, downloaded but not loaded.
    static let unloadedModel = """
        {"id":"gemma-3-12b-it","object":"model","type":"llm","state":"not-loaded","max_context_length":8192}
        """

    /// A server that will not compile the schema for the loaded engine.
    static let schemaRejected = """
        {"error":"'response_format.json_schema' is not supported by the loaded model"}
        """

    static let blockAnswer =
        ###"{"markdown":"## Der TLB als Cache der Übersetzung\nDer **TLB** hält die letzten Übersetzungen.\n- Verdrängung nach pseudo-LRU"}"###
}

private func endpoint() throws -> LMStudioEndpoint {
    try LMStudioEndpoint(address: LMStudioEndpoint.defaultBaseAddress)
}

private func body(of request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

// MARK: - The address

@Suite("LM Studio endpoint")
struct LMStudioEndpointTests {

    /// The design draws `/v1` in the settings field and the locked decision
    /// posts to `/api/v0`. Both, at once, is this type's job.
    @Test("The stored /v1 address posts completions to /api/v0")
    func pathIsSwapped() throws {
        let endpoint = try LMStudioEndpoint(address: "http://localhost:1234/v1")

        #expect(endpoint.chatCompletions.absoluteString == "http://localhost:1234/api/v0/chat/completions")
        #expect(endpoint.models.absoluteString == "http://localhost:1234/v1/models")
        #expect(endpoint.model("qwen").absoluteString == "http://localhost:1234/api/v0/models/qwen")
    }

    @Test("The address the user typed does not have to be tidy", arguments: [
        "http://localhost:1234/v1",
        "http://localhost:1234/v1/",
        "http://localhost:1234",
        "http://localhost:1234/",
        "http://localhost:1234/api/v0",
    ])
    func addressesAreNormalised(_ address: String) throws {
        let endpoint = try LMStudioEndpoint(address: address)

        #expect(endpoint.chatCompletions.absoluteString == "http://localhost:1234/api/v0/chat/completions")
        #expect(endpoint.models.absoluteString == "http://localhost:1234/v1/models")
    }

    @Test("Surrounding whitespace is not an invalid address")
    func whitespaceIsTrimmed() throws {
        let endpoint = try LMStudioEndpoint(address: "  http://localhost:1234/v1  ")
        #expect(endpoint.models.absoluteString == "http://localhost:1234/v1/models")
    }

    @Test("Every spelling of this machine is accepted", arguments: [
        "http://127.0.0.1:1234/v1",
        "http://localhost:1/v1",
        "https://localhost:1234/v1",
    ])
    func localAddressesAreAccepted(_ address: String) throws {
        #expect(throws: Never.self) { try LMStudioEndpoint(address: address) }
    }

    /// Hard rule 9. There is no network code in Retain beyond this machine, and
    /// the refusal happens before a socket is opened.
    @Test("Anything that is not this machine is refused", arguments: [
        "http://192.168.1.50:1234/v1",
        "https://api.openai.com/v1",
        "http://0.0.0.0:1234/v1",
        "http://localhost.attacker.example/v1",
        "file:///tmp/v1",
        "not a url at all",
    ])
    func remoteAddressesAreRefused(_ address: String) {
        #expect(throws: SummarizationError.notLocalhost) {
            try LMStudioEndpoint(address: address)
        }
    }
}

// MARK: - Stop reasons

@Suite("Stop reasons")
struct StopReasonTests {

    @Test("The reasons that mean the model finished")
    func completeReasons() {
        #expect(StopReason.parse("eosFound") == .endOfSequence)
        #expect(StopReason.parse("stopStringFound") == .stopString)
        #expect(StopReason.parse("toolCalls") == .toolCalls)
        #expect(StopReason.parse("eosFound").isComplete)
    }

    /// The pair hard rule 13 is about. `truncateMiddle` would have produced
    /// neither of these and summarised half a lesson instead.
    @Test("The reasons that mean it stopped short")
    func truncatingReasons() {
        #expect(StopReason.parse("maxPredictedTokensReached") == .maxPredictedTokens)
        #expect(StopReason.parse("contextLengthReached") == .contextLengthReached)
        #expect(!StopReason.parse("maxPredictedTokensReached").isComplete)
        #expect(!StopReason.parse("contextLengthReached").isComplete)
        #expect(!StopReason.parse("failed").isComplete)
        #expect(!StopReason.parse("modelUnloaded").isComplete)
    }

    /// Inventing a failure out of a string a future LM Studio added would throw
    /// away answers that are fine.
    @Test("An unknown reason counts as finished")
    func unknownReasonsAreComplete() {
        #expect(StopReason.parse("somethingNew") == .unknown("somethingNew"))
        #expect(StopReason.parse("somethingNew").isComplete)
        #expect(StopReason.parse(nil).isComplete)
    }

    /// Why Retain is on `/api/v0` at all: `length` is what `/v1` says both for
    /// "hit the token cap" and for "ran out of context".
    @Test("finish_reason is coarser than stop_reason and still catches a cut-off")
    func finishReasonFallback() {
        #expect(StopReason.parseFinishReason("stop") == .endOfSequence)
        #expect(StopReason.parseFinishReason("length") == .maxPredictedTokens)
        #expect(!StopReason.parseFinishReason("length").isComplete)
    }
}

// MARK: - The client

@Suite("LM Studio client")
struct LMStudioBackendTests {

    // MARK: Models

    @Test("Models come from /v1/models")
    func modelsAreListed() async throws {
        let transport = RecordedTransport(Recorded.models)
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        let models = try await backend.availableModels()

        #expect(models.map(\.id) == [
            "qwen2.5-7b-instruct", "gemma-3-12b-it", "text-embedding-nomic-embed-text-v1.5",
        ])
        #expect(transport.requests.first?.url?.path == "/v1/models")
        #expect(transport.requests.first?.httpMethod == "GET")
    }

    @Test("The connection test reports what the design draws")
    func connectionTestReportsModelCount() async throws {
        let backend = LMStudioBackend(
            endpoint: try endpoint(),
            transport: RecordedTransport(Recorded.models),
            apiKey: { nil }
        )

        let report = try await backend.checkConnection()
        #expect(report.modelCount == 3)
        #expect(report.latency >= 0)
    }

    @Test("A server that is not there is not there")
    func unreachableServer() async throws {
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: RecordedTransport([]), apiKey: { nil })

        await #expect(throws: SummarizationError.unreachable) {
            try await backend.availableModels()
        }
    }

    /// The number the context pre-flight is measured against: what the model
    /// was *loaded* with, not what it could support.
    @Test("The loaded context length is read, not the advertised one")
    func loadedContextLengthIsRead() async throws {
        let backend = LMStudioBackend(
            endpoint: try endpoint(),
            transport: RecordedTransport(Recorded.loadedModel),
            apiKey: { nil }
        )

        #expect(try await backend.loadedContextLength(of: "qwen2.5-7b-instruct") == 4096)
    }

    @Test("A model that is not loaded has no loaded context length")
    func unloadedModelHasNoContextLength() async throws {
        let backend = LMStudioBackend(
            endpoint: try endpoint(),
            transport: RecordedTransport(Recorded.unloadedModel),
            apiKey: { nil }
        )

        #expect(try await backend.loadedContextLength(of: "gemma-3-12b-it") == nil)
    }

    @Test("A model the server has never heard of is not an error")
    func unknownModelIsNotAnError() async throws {
        let backend = LMStudioBackend(
            endpoint: try endpoint(),
            transport: RecordedTransport([.init(404, "{\"error\":\"model not found\"}")]),
            apiKey: { nil }
        )

        #expect(try await backend.loadedContextLength(of: "nothing") == nil)
    }

    // MARK: The request

    @Test("A completion goes to /api/v0 with the locked settings on it")
    func requestShapeIsCorrect() async throws {
        let transport = RecordedTransport(Recorded.completion(content: Recorded.blockAnswer))
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        _ = try await backend.structuredReply(
            to: ChatConversation([.user("Fasse zusammen.")]),
            model: "qwen2.5-7b-instruct",
            schema: NoteReduction.blockSchema,
            as: NoteReduction.BlockAnswer.self
        )

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v0/chat/completions")

        let sent = try body(of: request)
        #expect(sent["model"] as? String == "qwen2.5-7b-instruct")
        #expect(sent["stream"] as? Bool == false)
        // Hard rule 13. `truncateMiddle` is what must never be sent.
        #expect(sent["contextOverflowPolicy"] as? String == "stopAtLimit")

        let format = try #require(sent["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["strict"] as? Bool == true)
        #expect(schema["name"] as? String == "note_block")
    }

    /// The order a constrained decoder makes the model write its fields in has
    /// to survive all the way to the socket, not only as far as the schema
    /// constant.
    @Test("The schema reaches the wire in the order it was written")
    func schemaOrderSurvivesTheRequest() throws {
        let sent = LMStudioBackend.requestBody(
            model: "qwen2.5-7b-instruct",
            messages: [.user("Fasse zusammen.")],
            mode: .jsonSchema,
            schema: NoteReduction.notesSchema
        ).serialized

        let topic = try #require(sent.range(of: "\"topic\""))
        let markdown = try #require(sent.range(of: "\"markdown\""))

        #expect(topic.lowerBound < markdown.lowerBound)
    }

    @Test("An API key is sent as a bearer token, and only when there is one")
    func apiKeyIsSentWhenPresent() async throws {
        let withKey = RecordedTransport(Recorded.models)
        _ = try await LMStudioBackend(endpoint: try endpoint(), transport: withKey, apiKey: { "lm-secret" })
            .availableModels()

        let without = RecordedTransport(Recorded.models)
        _ = try await LMStudioBackend(endpoint: try endpoint(), transport: without, apiKey: { nil })
            .availableModels()

        #expect(withKey.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer lm-secret")
        #expect(without.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("An empty key is no key")
    func emptyKeyIsNotSent() async throws {
        let transport = RecordedTransport(Recorded.models)
        _ = try await LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { "" })
            .availableModels()

        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Summarizing without a model chosen asks for one instead of guessing")
    func noModelSelected() async throws {
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: RecordedTransport([]), apiKey: { nil })

        await #expect(throws: SummarizationError.noModelSelected) {
            try await backend.structuredReply(
                to: ChatConversation([.user("x")]),
                model: "  ",
                schema: NoteReduction.blockSchema,
                as: NoteReduction.BlockAnswer.self
            )
        }
    }

    // MARK: The ladder

    @Test("The first rung answers and nothing else is tried")
    func strictRungAnswers() async throws {
        let transport = RecordedTransport(Recorded.completion(content: Recorded.blockAnswer))
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        let reply = try await backend.structuredReply(
            to: ChatConversation([.user("Fasse zusammen.")]),
            model: "qwen2.5-7b-instruct",
            schema: NoteReduction.blockSchema,
            as: NoteReduction.BlockAnswer.self
        )

        #expect(reply.mode == .jsonSchema)
        #expect(reply.stopReason == .endOfSequence)
        #expect(reply.contextLength == 8192)
        #expect(reply.answer.markdown.contains("**TLB**"))
        #expect(transport.requests.count == 1)
    }

    @Test("A server that will not compile the schema drops to json_object")
    func secondRungAnswers() async throws {
        let transport = RecordedTransport([
            .init(400, Recorded.schemaRejected),
            .init(200, Recorded.completion(content: Recorded.blockAnswer)),
        ])
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        let reply = try await backend.structuredReply(
            to: ChatConversation([.user("Fasse zusammen.")]),
            model: "qwen2.5-7b-instruct",
            schema: NoteReduction.blockSchema,
            as: NoteReduction.BlockAnswer.self
        )

        #expect(reply.mode == .jsonObject)
        #expect(transport.requests.count == 2)

        let second = try body(of: transport.requests[1])
        let format = try #require(second["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_object")
        #expect(format["json_schema"] == nil)

        // `json_object` mode is rejected outright by servers unless the prompt
        // mentions JSON, so the schema is spelled out in a message instead.
        let messages = try #require(second["messages"] as? [[String: Any]])
        let instruction = try #require(messages.last?["content"] as? String)
        #expect(instruction.contains("JSON Schema"))
    }

    @Test("A model that ignores both formats is still read from its prose")
    func thirdRungAnswers() async throws {
        let prose = """
            Gerne! Hier ist die Zusammenfassung als JSON:

            ```json
            \(Recorded.blockAnswer)
            ```

            Sag Bescheid, wenn du noch etwas brauchst.
            """

        let transport = RecordedTransport([
            .init(400, Recorded.schemaRejected),
            .init(400, "{\"error\":\"'response_format' is not supported\"}"),
            .init(200, Recorded.completion(content: prose)),
        ])
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        let reply = try await backend.structuredReply(
            to: ChatConversation([.user("Fasse zusammen.")]),
            model: "qwen2.5-7b-instruct",
            schema: NoteReduction.blockSchema,
            as: NoteReduction.BlockAnswer.self
        )

        #expect(reply.mode == .freeText)
        #expect(reply.answer.markdown.hasPrefix("## Der TLB als Cache der Übersetzung"))
        #expect(transport.requests.count == 3)

        // No response_format at all on the last rung: a server that does not
        // know the field is likelier to reject the request than to ignore it.
        let third = try body(of: transport.requests[2])
        #expect(third["response_format"] == nil)
    }

    @Test("A reply that is not an answer at all fails after all three rungs")
    func malformedAnswerExhaustsTheLadder() async throws {
        let apology = "Es tut mir leid, dazu kann ich nichts sagen."
        let transport = RecordedTransport([
            .init(200, Recorded.completion(content: apology)),
            .init(200, Recorded.completion(content: apology)),
            .init(200, Recorded.completion(content: apology)),
        ])
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        await #expect(throws: SummarizationError.unreadableAnswer) {
            try await backend.structuredReply(
                to: ChatConversation([.user("Fasse zusammen.")]),
                model: "qwen2.5-7b-instruct",
                schema: NoteReduction.blockSchema,
                as: NoteReduction.BlockAnswer.self
            )
        }
        #expect(transport.requests.count == 3)
    }

    @Test("A reply whose envelope is not even JSON does not crash the lesson")
    func malformedEnvelope() async throws {
        let transport = RecordedTransport([
            .init(200, "<html><body>502 Bad Gateway</body></html>"),
            .init(200, "<html><body>502 Bad Gateway</body></html>"),
            .init(200, "<html><body>502 Bad Gateway</body></html>"),
        ])
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        await #expect(throws: SummarizationError.unreadableAnswer) {
            try await backend.structuredReply(
                to: ChatConversation([.user("x")]),
                model: "qwen2.5-7b-instruct",
                schema: NoteReduction.blockSchema,
                as: NoteReduction.BlockAnswer.self
            )
        }
    }

    @Test("A status the ladder cannot fix is not retried")
    func fatalStatusStops() async throws {
        let transport = RecordedTransport([.init(401, "{\"error\":\"unauthorized\"}")])
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        await #expect(throws: SummarizationError.httpStatus(401)) {
            try await backend.structuredReply(
                to: ChatConversation([.user("x")]),
                model: "qwen2.5-7b-instruct",
                schema: NoteReduction.blockSchema,
                as: NoteReduction.BlockAnswer.self
            )
        }
        #expect(transport.requests.count == 1)
    }

    // MARK: Stopping short

    /// The failure hard rule 13 exists for. The answer below parses perfectly
    /// well — it is simply half a lesson, and without this check it would have
    /// gone into the notes as the whole one.
    @Test("A model that ran out of context fails instead of answering")
    func contextOverflowIsAnError() async throws {
        let halfAnAnswer = """
            {"markdown":"## Seitenersetzung\\nDie Auswahl der zu verdrängenden Seite entscheidet über die Trefferrate."}
            """
        let transport = RecordedTransport(
            Recorded.completion(content: halfAnAnswer, stopReason: "contextLengthReached", finishReason: "length")
        )
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        await #expect(throws: SummarizationError.truncated(.contextLengthReached)) {
            try await backend.structuredReply(
                to: ChatConversation([.user("x")]),
                model: "qwen2.5-7b-instruct",
                schema: NoteReduction.blockSchema,
                as: NoteReduction.BlockAnswer.self
            )
        }

        // Not retried down the ladder: a looser response format does not make
        // more room, and the reduce model is expensive to run twice.
        #expect(transport.requests.count == 1)
    }

    @Test("A model that hit its token cap fails the same way")
    func tokenCapIsAnError() async throws {
        let transport = RecordedTransport(
            Recorded.completion(content: Recorded.blockAnswer, stopReason: "maxPredictedTokensReached", finishReason: "length")
        )
        let backend = LMStudioBackend(endpoint: try endpoint(), transport: transport, apiKey: { nil })

        await #expect(throws: SummarizationError.truncated(.maxPredictedTokens)) {
            try await backend.structuredReply(
                to: ChatConversation([.user("x")]),
                model: "qwen2.5-7b-instruct",
                schema: NoteReduction.blockSchema,
                as: NoteReduction.BlockAnswer.self
            )
        }
    }

    /// A build that stops sending `stats` must not turn every summary into a
    /// crash — it degrades to `finish_reason`, which is coarser and still
    /// catches a cut-off.
    @Test("A reply with no stats falls back to finish_reason")
    func statsAreOptional() async throws {
        let truncated = RecordedTransport(
            Recorded.completion(content: Recorded.blockAnswer, stopReason: nil, finishReason: "length")
        )
        let finished = RecordedTransport(
            Recorded.completion(content: Recorded.blockAnswer, stopReason: nil, finishReason: "stop", loadedContextLength: nil)
        )

        await #expect(throws: SummarizationError.truncated(.maxPredictedTokens)) {
            try await LMStudioBackend(endpoint: try endpoint(), transport: truncated, apiKey: { nil })
                .structuredReply(
                    to: ChatConversation([.user("x")]),
                    model: "m",
                    schema: NoteReduction.blockSchema,
                    as: NoteReduction.BlockAnswer.self
                )
        }

        let reply = try await LMStudioBackend(endpoint: try endpoint(), transport: finished, apiKey: { nil })
            .structuredReply(
                to: ChatConversation([.user("x")]),
                model: "m",
                schema: NoteReduction.blockSchema,
                as: NoteReduction.BlockAnswer.self
            )
        #expect(reply.stopReason == .endOfSequence)
        #expect(reply.contextLength == nil)
    }
}
