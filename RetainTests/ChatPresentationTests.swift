import Foundation
import Testing

@testable import Retain

/// What the chat rail does between a question being sent and an answer
/// arriving.
///
/// **Nothing, is what it did.** `ask()` read the turns back from the chat actor
/// only once the answer had landed, so typing a question and pressing Return
/// produced no visible change for as long as the model took — which for a cold
/// 20B model is twenty seconds. The comment above that line claimed the
/// opposite, which is worse than no comment.
@Suite("Chat presentation")
struct ChatPresentationTests {

    /// A backend that does not answer until it is let go, so the window in
    /// which the question has to already be on screen can be looked at.
    private nonisolated final class HeldBackend: SummarizationBackend, @unchecked Sendable {

        private let released: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation

        init() {
            var continuation: AsyncStream<Void>.Continuation!
            released = AsyncStream { continuation = $0 }
            self.continuation = continuation
        }

        func release() { continuation.yield() }

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
            for await _ in released { break }
            throw SummarizationError.unreachable
        }
    }

    @Test("The question is in the rail before the answer is")
    func theQuestionShowsAtOnce() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let course = try await StoreFixture.course(in: database, term: term, name: "Biologie")
        var recording = try await StoreFixture.recording(in: database, course: course, term: term)
        let id = try #require(recording.id)

        // The chat refuses to answer until the lecture has stopped — see
        // `ChatAvailability` — and `startRecording` leaves the row saying it is
        // still running.
        recording.state = .done
        recording = try await LibraryRepository(database).save(recording)

        let transcript = TranscriptRepository(database)
        try await transcript.append(StoreFixture.line("Die Algenzellen leben in der Koralle", at: 0), to: id)
        _ = try await NoteRepository(database).append(
            StoredNoteBlock(recordingID: id, position: 1, startTime: 0, endTime: 60, markdown: "## Korallen"),
            to: id
        )

        let backend = HeldBackend()
        let chat = RecordingChat(
            backend: backend,
            model: "small",
            material: .init(notes: nil, transcript: [], isRecording: false)
        )

        let model = await RecordingDetailModel(recording: recording, database: database, chat: chat)
        await model.load()
        await MainActor.run { model.question = "Was ist Symbiose?" }

        let asking = Task { await model.ask() }

        // Let `ask()` get as far as the request, which is where it parks.
        //
        // Bounded, and that matters: `ask()` returns straight away when the
        // chat is not ready, and an unbounded spin on a flag that will never
        // flip hangs the whole suite rather than failing this one test. It did.
        let deadline = Date().addingTimeInterval(5)
        while await model.isAnswering == false, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await model.isAnswering, "ask() never reached the request")

        let turns = await model.turns
        #expect(turns.last?.author == .you)
        #expect(turns.last?.text == "Was ist Symbiose?")

        backend.release()
        await asking.value
    }
}
