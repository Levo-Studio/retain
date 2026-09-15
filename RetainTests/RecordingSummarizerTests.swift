import Foundation
import Testing

@testable import Retain

/// A backend that answers from canned replies and remembers what it was asked.
///
/// This is what the protocol in `SummarizationBackend` is for: the map, the
/// reduce, the chat and the context pre-flight are all testable without LM
/// Studio being installed, let alone running.
nonisolated final class StubBackend: SummarizationBackend, @unchecked Sendable {

    private let lock = NSLock()
    private var answers: [String]
    private var asked: [String] = []
    private var prompts: [ChatConversation] = []

    /// What `loadedContextLength(of:)` reports. `nil` means the server did not
    /// say, which is the case the pre-flight has to skip rather than guess at.
    let contextLength: Int?

    init(answers: [String], contextLength: Int? = nil) {
        self.answers = answers
        self.contextLength = contextLength
    }

    var models: [String] { lock.withLock { asked } }
    var conversations: [ChatConversation] { lock.withLock { prompts } }

    func availableModels() async throws -> [LanguageModelDescriptor] {
        [LanguageModelDescriptor(id: "small", contextLength: nil)]
    }

    func loadedContextLength(of model: String) async throws -> Int? {
        contextLength
    }

    /// A stub has nothing to read off disk. What the real one does here is wait
    /// — see `LMStudioBackend.load` — which is exactly why it is a verb of its
    /// own rather than something the first summary happens to trigger.
    func load(_ model: String) async throws {}

    func checkConnection() async throws -> ConnectionReport {
        ConnectionReport(modelCount: 1, latency: 0.24)
    }

    func structuredReply<Answer: Decodable & Sendable>(
        to conversation: ChatConversation,
        model: String,
        schema: SchemaDescription,
        as answer: Answer.Type
    ) async throws -> StructuredReply<Answer> {
        let json: String = try lock.withLock {
            asked.append(model)
            prompts.append(conversation)
            guard !answers.isEmpty else { throw SummarizationError.unreachable }
            return answers.removeFirst()
        }

        return StructuredReply(
            answer: try StructuredJSON.decode(Answer.self, from: json),
            mode: .jsonSchema,
            stopReason: .endOfSequence,
            contextLength: contextLength
        )
    }
}

private let blockReply = """
    {"markdown":"## Der TLB als Cache\\nDer **TLB** hält die letzten Übersetzungen."}
    """

private let notesReply = """
    {"topic":"Virtueller Speicher und Paging","markdown":"## Adressräume\\nJeder Prozess sieht einen **Adressraum**."}
    """

private let configuration = RecordingSummarizer.Configuration(smallModel: "small", largeModel: "large")

private func block(_ number: Int = 1) -> TranscriptBlock {
    TranscriptBlock(
        number: number,
        lines: [TranscriptLine(start: 0, end: 180, text: "Der TLB hält die letzten Übersetzungen.")],
        markers: [],
        closing: .speechBudget
    )
}

private func card(_ number: Int = 1) -> NoteBlock {
    NoteBlock(number: number, markdown: "## Adressräume\nAbsatz.", start: 0, end: 180)
}

@Suite("Recording summarizer")
struct RecordingSummarizerTests {

    @Test("A block is summarised into the card the design draws")
    func mapProducesACard() async throws {
        let backend = StubBackend(answers: [blockReply])
        let summarizer = RecordingSummarizer(backend: backend, configuration: configuration)

        let note = try await summarizer.summarise(block(2))

        #expect(note.number == 2)
        #expect(note.heading == "Der TLB als Cache")
        #expect(note.markdown.contains("**TLB**"))
        #expect(note.start == 0)
        #expect(note.end == 180)
    }

    /// A block has to be summarised while the recording is still running, so
    /// the map never gets the large model — not even on mains.
    @Test("The map always uses the small model")
    func mapAlwaysUsesTheSmallModel() async throws {
        let backend = StubBackend(answers: [blockReply, blockReply])
        let summarizer = RecordingSummarizer(backend: backend, configuration: configuration)

        _ = try await summarizer.summarise(block(1))
        _ = try await summarizer.summarise(block(2))

        #expect(backend.models == ["small", "small"])
    }

    @Test("The reduce uses the model the power source allows", arguments: [ModelSize.small, .large])
    func reduceUsesTheModelItWasGiven(_ size: ModelSize) async throws {
        let backend = StubBackend(answers: [notesReply])
        let summarizer = RecordingSummarizer(backend: backend, configuration: configuration)

        _ = try await summarizer.reduce(
            notes: [card()],
            transcript: [TranscriptLine(start: 0, end: 4, text: "Der Adressraum ist eine Abmachung.")],
            using: size
        )

        #expect(backend.models == [size == .large ? "large" : "small"])
    }

    @Test("The reduce carries the cards and the markers into the notes")
    func reduceCarriesEverything() async throws {
        let backend = StubBackend(answers: [notesReply])
        let summarizer = RecordingSummarizer(backend: backend, configuration: configuration)

        let notes = try await summarizer.reduce(
            notes: [card()],
            transcript: [],
            markers: [RecordingMarker(time: 90, text: "klausurrelevant")],
            using: .small
        )

        #expect(notes.topic == "Virtueller Speicher und Paging")
        #expect(notes.markers.count == 1)
        #expect(notes.blocks.count == 1)
        #expect(notes.chapters.first?.hasMarker == true)
    }

    /// `stopAtLimit` reports an overflow rather than hiding it — but it reports
    /// it after the large model has already run for two minutes. This is the
    /// same answer, before the wait.
    @Test("A recording that cannot fit is refused before the model runs")
    func reduceRefusesAnImpossiblePrompt() async throws {
        let backend = StubBackend(answers: [notesReply], contextLength: 512)
        let summarizer = RecordingSummarizer(backend: backend, configuration: configuration)

        let long = (0..<400).map {
            TranscriptLine(start: Double($0) * 10, end: Double($0) * 10 + 9, text: "Ein ziemlich langer Satz über Seitenersetzung.")
        }

        do {
            _ = try await summarizer.reduce(notes: [card()], transcript: long, using: .large)
            Issue.record("A recording far larger than the context was accepted")
        } catch SummarizationError.contextTooSmall(let needed, let available) {
            #expect(needed > available)
            #expect(available == TokenBudget.promptAllowance(of: 512))
        }

        // The model was never asked, which is the point: the wait is what this
        // check saves.
        #expect(backend.models.isEmpty)
    }

    @Test("A server that does not say how much context it has is not second-guessed")
    func silentServerSkipsThePreflight() async throws {
        let backend = StubBackend(answers: [notesReply], contextLength: nil)
        let summarizer = RecordingSummarizer(backend: backend, configuration: configuration)

        let long = (0..<400).map {
            TranscriptLine(start: Double($0) * 10, end: Double($0) * 10 + 9, text: "Ein ziemlich langer Satz über Seitenersetzung.")
        }

        _ = try await summarizer.reduce(notes: [card()], transcript: long, using: .large)
        #expect(backend.models == ["large"])
    }

    @Test("A model that cannot be reached is reported, not swallowed")
    func unreachableBackendThrows() async throws {
        let summarizer = RecordingSummarizer(backend: StubBackend(answers: []), configuration: configuration)

        await #expect(throws: SummarizationError.unreachable) {
            try await summarizer.summarise(block())
        }
    }
}
