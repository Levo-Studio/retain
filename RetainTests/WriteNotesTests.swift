import Defaults
import Foundation
import GRDB
import Testing

@testable import Retain

/// Writing a finished recording's notes after the fact.
///
/// **The notes could silently never arrive.** They are made during the lecture,
/// one block at a time, and a block the model could not answer was marked as
/// waiting — beside a comment saying summaries are caught up once the
/// connection is back. Nothing caught them up. A lecture recorded while LM
/// Studio was unreachable ended with a full transcript, no notes, and a window
/// whose only word on the subject was that the notes had not been written yet.
///
/// That happened on the owner's own machine, with 33 lines of transcript and
/// zero note blocks, because the API key had been deleted and every request
/// came back 401.
@Suite("Writing notes after the lecture")
struct WriteNotesTests {

    private func recordingWithTranscript(
        in database: RetainDatabase,
        lines: Int = 12
    ) async throws -> Recording {
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let course = try await StoreFixture.course(in: database, term: term, name: "Biologie")
        let recording = try await StoreFixture.recording(
            in: database,
            course: course,
            term: term,
            at: StoreFixture.instant(2026, 9, 15, 8, 28)
        )

        let transcript = TranscriptRepository(database)
        let id = try #require(recording.id)
        for index in 0..<lines {
            try await transcript.append(
                StoreFixture.line("Die Algenzellen leben in der Koralle \(index)", at: Double(index) * 20),
                to: id
            )
        }
        return recording
    }

    // MARK: - When it is offered

    @Test("It is offered for a recording with a transcript and no notes")
    func offeredWhenThereAreNoNotes() async throws {
        let database = try StoreFixture.database()
        let recording = try await recordingWithTranscript(in: database)

        let model = await RecordingDetailModel(recording: recording, database: database)
        await model.load()

        #expect(await model.blocks.isEmpty)
        #expect(await model.canWriteNotes)
    }

    @Test("It is not offered for a recording that has no transcript")
    func notOfferedWithoutATranscript() async throws {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let course = try await StoreFixture.course(in: database, term: term, name: "Biologie")
        let recording = try await StoreFixture.recording(in: database, course: course, term: term)

        let model = await RecordingDetailModel(recording: recording, database: database)
        await model.load()

        // There is nothing to summarise, and a button that can only fail is
        // worse than no button.
        #expect(await model.canWriteNotes == false)
    }

    @Test("It is not offered once the notes exist")
    func notOfferedWhenNotesExist() async throws {
        let database = try StoreFixture.database()
        let recording = try await recordingWithTranscript(in: database)
        let id = try #require(recording.id)

        _ = try await NoteRepository(database).append(
            StoredNoteBlock(
                recordingID: id,
                position: 1,
                startTime: 0,
                endTime: 120,
                markdown: "## Korallen\n\nAlgenzellen leben in der Koralle."
            ),
            to: id
        )

        let model = await RecordingDetailModel(recording: recording, database: database)
        await model.load()

        #expect(await model.blocks.isEmpty == false)
        // Rewriting notes that exist would take the highlights hanging off them
        // with it. That is a different action and needs its own confirmation.
        #expect(await model.canWriteNotes == false)
    }

    // MARK: - What it says when it cannot run

    @Test("With no model chosen it says so, and says where to choose one")
    func noModelChosenIsExplained() async throws {
        let database = try StoreFixture.database()
        let recording = try await recordingWithTranscript(in: database)

        let model = await RecordingDetailModel(recording: recording, database: database)
        await model.load()

        // `SummarizerFactory` reads the chosen model out of settings, and a
        // fresh install has none. The old behaviour was to do nothing at all.
        let name = Defaults[.languageModelName]
        Defaults[.languageModelName] = ""
        defer { Defaults[.languageModelName] = name }

        await model.writeNotes()

        guard case .failed(let reason) = await model.noteWriting else {
            Issue.record("writing notes with no model chosen reported no failure")
            return
        }
        #expect(reason.contains("Settings"))
        #expect(await model.blocks.isEmpty)
    }
}
