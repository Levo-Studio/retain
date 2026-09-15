import Foundation
import Testing

@testable import Retain

/// Blocks the model could not be reached for, and what happens to them
/// afterwards.
///
/// **Nothing did.** `replaceNote` marks such a block `deferred` rather than
/// dropping it, beside a comment explaining that board 07's dialog promises
/// "summaries are caught up once the connection is back". Nothing caught them
/// up. A lecture recorded while LM Studio was unreachable ended with every card
/// saying it was being written, for the rest of the hour and then for ever —
/// which is exactly what the owner reported as the notes column freezing.
@Suite("Deferred note blocks")
struct DeferredNotesTests {

    /// Refuses the first `failures` requests, then answers.
    private nonisolated final class FlakyBackend: SummarizationBackend, @unchecked Sendable {

        private let lock = NSLock()
        private var remainingFailures: Int
        private var requestCount = 0

        var requests: Int { lock.withLock { requestCount } }

        init(failures: Int) { remainingFailures = failures }

        func availableModels() async throws -> [LanguageModelDescriptor] {
            [LanguageModelDescriptor(id: "small", contextLength: 8192, state: .loaded)]
        }

        func loadedContextLength(of model: String) async throws -> Int? { 8192 }
        func load(_ model: String) async throws {}
        func checkConnection() async throws -> ConnectionReport {
            ConnectionReport(modelCount: 1, latency: 0)
        }

        func structuredReply<Answer: Decodable & Sendable>(
            to conversation: ChatConversation,
            model: String,
            schema: SchemaDescription,
            as answer: Answer.Type
        ) async throws -> StructuredReply<Answer> {
            // `withLock` rather than lock/unlock: the plain pair is unavailable
            // from an async context, and for good reason — an await between
            // them would hold the lock across a suspension.
            let shouldFail = lock.withLock {
                requestCount += 1
                guard remainingFailures > 0 else { return false }
                remainingFailures -= 1
                return true
            }

            if shouldFail { throw SummarizationError.unreachable }

            let json = """
                {"heading": "Korallen", "markdown": "## Korallen\\n\\nAlgen leben in der Koralle."}
                """
            return StructuredReply(
                answer: try StructuredJSON.decode(Answer.self, from: json),
                mode: .jsonSchema,
                stopReason: .endOfSequence,
                contextLength: 8192
            )
        }
    }

    private func lines(_ count: Int) -> [TranscriptLine] {
        (0..<count).map { index in
            TranscriptLine(
                start: Double(index) * 30,
                end: Double(index) * 30 + 25,
                text: "Die Algenzellen leben in der Koralle, Satz \(index)",
                speaker: .lecturer
            )
        }
    }

    // MARK: -

    @Test("A block the model refused is waiting, not being written")
    func aRefusedBlockIsDeferred() async throws {
        let session = LectureSession(
            course: Course(name: "Biologie", color: .accent),
            lines: lines(30),
            notes: [NoteBlock(number: 1, markdown: "", start: 0, end: 300, state: .deferred)]
        )
        session.summarizer = RecordingSummarizer(
            backend: FlakyBackend(failures: 99),
            configuration: .init(smallModel: "small", largeModel: "small")
        )

        await session.retryDeferredBlocks()

        // Still waiting, and still saying so. The two states used to be drawn
        // identically, which is what made a failure look like work in progress
        // that never ended.
        #expect(session.notes.first?.state == .deferred)
    }

    @Test("A waiting block is sent again and fills itself in")
    func aDeferredBlockIsCaughtUp() async throws {
        let session = LectureSession(
            course: Course(name: "Biologie", color: .accent),
            lines: lines(30),
            notes: [NoteBlock(number: 1, markdown: "", start: 0, end: 300, state: .deferred)]
        )
        session.summarizer = RecordingSummarizer(
            backend: FlakyBackend(failures: 0),
            configuration: .init(smallModel: "small", largeModel: "small")
        )

        await session.retryDeferredBlocks()

        let block = try #require(session.notes.first)
        #expect(block.state == .written)
        #expect(block.markdown.contains("Korallen"))
    }

    @Test("A lecture with nothing waiting sends no request at all")
    func nothingWaitingCostsNothing() async throws {
        let backend = FlakyBackend(failures: 0)
        let session = LectureSession(
            course: Course(name: "Biologie", color: .accent),
            lines: lines(30),
            notes: [NoteBlock(number: 1, markdown: "## Da", start: 0, end: 300, state: .written)]
        )
        session.summarizer = RecordingSummarizer(
            backend: backend,
            configuration: .init(smallModel: "small", largeModel: "small")
        )

        await session.retryDeferredBlocks()

        // This runs on every finished transcript line. It must be free when
        // there is nothing to catch up on.
        #expect(backend.requests == 0)
    }
}
