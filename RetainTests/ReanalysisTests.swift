import Defaults
import Foundation
import Testing

@testable import Retain

/// Writing a recording's notes again.
///
/// The one action in the detail window that costs something: the transcript is
/// safe, but the highlights are not. A highlight is a passage somebody marked
/// by hand, it hangs off the note block it was marked in, and replacing the
/// blocks takes it with them. Nobody can mark a passage again in notes they no
/// longer have — so it is counted before the question is asked, the way a
/// term's and a recording's deletion are.
@Suite("Re-analysing a recording")
struct ReanalysisTests {

    private func recording(
        in database: RetainDatabase,
        lines: Int = 6,
        notes: Int = 0
    ) async throws -> Recording {
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let course = try await StoreFixture.course(in: database, term: term, name: "Biologie")
        var recording = try await StoreFixture.recording(in: database, course: course, term: term)
        recording.state = .done
        recording = try await LibraryRepository(database).save(recording)

        let id = try #require(recording.id)
        let transcript = TranscriptRepository(database)
        for index in 0..<lines {
            try await transcript.append(
                StoreFixture.line("Die Algenzellen leben in der Koralle \(index)", at: Double(index) * 20),
                to: id
            )
        }

        let repository = NoteRepository(database)
        for index in 0..<notes {
            _ = try await repository.append(
                StoredNoteBlock(
                    recordingID: id,
                    position: index + 1,
                    startTime: Double(index) * 120,
                    endTime: Double(index) * 120 + 110,
                    markdown: "## Korallen \(index)\n\nAlgen leben in der Koralle."
                ),
                to: id
            )
        }

        return recording
    }

    // MARK: - What the confirmation is told

    @Test("It counts the transcript, the blocks and the marked passages")
    func theImpactCountsWhatIsAtStake() async throws {
        let database = try StoreFixture.database()
        let recording = try await recording(in: database, lines: 6, notes: 2)
        let id = try #require(recording.id)

        let stored = try await NoteRepository(database).blocks(for: id)
        let block = try #require(stored.first)
        _ = try await NoteRepository(database).highlight(block, from: 3, to: 11)

        let model = await RecordingDetailModel(recording: recording, database: database)
        await model.load()

        let impact = await model.reanalysisImpact
        #expect(impact.transcriptLines == 6)
        #expect(impact.noteBlocks == 2)
        #expect(impact.highlights == 1)
        #expect(impact.isFirstTime == false)
    }

    @Test("A recording with no notes is the first-time case, with no warning")
    func theFirstTimeCaseIsNotAWarning() async throws {
        let database = try StoreFixture.database()
        let recording = try await recording(in: database, notes: 0)

        let model = await RecordingDetailModel(recording: recording, database: database)
        await model.load()

        let impact = await model.reanalysisImpact
        #expect(impact.isFirstTime)
        // Nothing is at stake, so the sentence that says something is must not
        // be there.
        let sentences = ReanalyseDialog.sentences(impact)
        #expect(!sentences.contains("cannot be marked again"))
        #expect(sentences.contains("not touched"))
    }

    @Test("Marked passages are named, and only when there are some")
    func theBodyNamesTheHighlights() {
        let with = ReanalyseDialog.sentences(
            ReanalysisImpact(noteBlocks: 4, highlights: 3, transcriptLines: 120)
        )
        #expect(with.contains("3"))
        #expect(with.contains("cannot be marked again"))

        let without = ReanalyseDialog.sentences(
            ReanalysisImpact(noteBlocks: 4, highlights: 0, transcriptLines: 120)
        )
        #expect(!without.contains("cannot be marked again"))
    }

    // MARK: - When it can be pressed

    @Test("It is offered whether or not notes exist, and refused without a transcript")
    func whenItIsOffered() async throws {
        let database = try StoreFixture.database()

        let withNotes = try await recording(in: database, lines: 6, notes: 2)
        let a = await RecordingDetailModel(recording: withNotes, database: database)
        await a.load()
        // The button used to live in the empty notes column, so it vanished the
        // moment it had worked once — and a recording whose notes are wrong is
        // exactly the one somebody wants to run again.
        #expect(await a.canReanalyse)

        let empty = try StoreFixture.database()
        let withoutTranscript = try await recording(in: empty, lines: 0, notes: 0)
        let b = await RecordingDetailModel(recording: withoutTranscript, database: empty)
        await b.load()
        #expect(await b.canReanalyse == false)
    }

    // MARK: - What it does

    @Test("The old blocks and their highlights go before the model is asked")
    func theOldNotesAreCleared() async throws {
        let database = try StoreFixture.database()
        let recording = try await recording(in: database, lines: 6, notes: 2)
        let id = try #require(recording.id)

        let repository = NoteRepository(database)
        let block = try #require(try await repository.blocks(for: id).first)
        _ = try await repository.highlight(block, from: 3, to: 11)

        let model = await RecordingDetailModel(recording: recording, database: database)
        await model.load()

        // No model is chosen, so the write fails right after the clear — which
        // is the sharpest version of this test: the notes are gone and nothing
        // has replaced them, and that has to be a state the window survives.
        let name = Defaults[.languageModelName]
        Defaults[.languageModelName] = ""
        defer { Defaults[.languageModelName] = name }

        await model.reanalyse()

        #expect(try await repository.blocks(for: id).isEmpty)
        #expect(try await repository.highlights(for: id).isEmpty)
        #expect(await model.blocks.isEmpty)
        guard case .failed = await model.noteWriting else {
            Issue.record("the failure after clearing was not reported")
            return
        }
    }
}
