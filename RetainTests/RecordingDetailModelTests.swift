import Foundation
import Testing

@testable import Retain

/// The notes of board 03, written the way the model actually writes them:
/// `##` headings, a paragraph, a list, one emphasised term.
private let firstCard = """
    ## Wann eine Seite verdrängt werden darf
    Die Auswahl der zu verdrängenden Seite entscheidet über die Trefferrate. \
    Praktisch verwendet werden Näherungen an **LRU**.

    - FIFO ist billig, leidet aber unter der Bélády-Anomalie
    - Second Chance prüft das Referenzbit, bevor verdrängt wird
    """

private let secondCard = """
    ## Working Set und Thrashing
    Das **Working Set** ist die Menge der Seiten, die ein Prozess in einem Zeitfenster anfasst.
    """

/// A card the model answered without a heading. It has no chapter row, and the
/// rail being one row short is the right answer rather than a row with an empty
/// label in it.
private let headlessCard = "Ein Absatz ohne Überschrift."

// MARK: -

@MainActor
@Suite("Recording detail")
struct RecordingDetailModelTests {

    private func loaded(
        state: RecordingState = .done,
        cards: [String] = [firstCard, secondCard],
        annotations: [(TimeInterval, String)] = [(3130, "Übungsblatt 5, Aufgabe 3 rechnet genau diesen Fall durch.")],
        chat: RecordingChat? = nil
    ) async throws -> RecordingDetailModel {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)

        var recording = library.recording
        recording.duration = 5520
        recording.state = state
        recording.topic = "Seitenersetzung und Working Set"
        try await LibraryRepository(database).save(recording)

        try await NoteRepository(database).replaceBlocks(
            cards.enumerated().map { index, markdown in
                StoreFixture.noteBlock(
                    markdown,
                    position: index,
                    startTime: TimeInterval(index) * 2700 + 240,
                    endTime: TimeInterval(index + 1) * 2700 + 240
                )
            },
            for: recordingID
        )

        try await TranscriptRepository(database).replaceLines([
            StoreFixture.line("Genau diese Menge nennen wir das Working Set.", at: 3130),
            StoreFixture.line("Über welches Zeitfenster misst man das?", at: 3168, speaker: .audience),
        ], for: recordingID)

        for (time, note) in annotations {
            _ = try await TranscriptRepository(database).annotate(at: time, note: note, in: recordingID)
        }

        let model = RecordingDetailModel(
            recording: try #require(try await LibraryRepository(database).recording(recordingID)),
            database: database,
            chat: chat
        )
        await model.load()
        return model
    }

    // MARK: - The chapter rail

    /// The rail is derived, never stored, so it cannot disagree with the notes.
    @Test("Every card with a heading becomes one chapter row, in order")
    func chaptersFromRealMarkdown() async throws {
        let model = try await loaded()

        #expect(model.chapters.map(\.title) == [
            "Wann eine Seite verdrängt werden darf",
            "Working Set und Thrashing",
        ])
        #expect(model.chapters.map(\.blockNumber) == [1, 2])
        #expect(model.chapters.map(\.time) == [240, 2940])
    }

    @Test("A card the model wrote without a heading has no row")
    func aCardWithNoHeading() async throws {
        let model = try await loaded(cards: [firstCard, headlessCard, secondCard])

        #expect(model.blocks.count == 3)
        #expect(model.chapters.count == 2)
        #expect(model.chapters.map(\.blockNumber) == [1, 3])
    }

    @Test("A chapter with something marked inside it carries the amber dot")
    func markerDot() async throws {
        let model = try await loaded()

        #expect(model.chapters[0].hasMarker == false)
        #expect(model.chapters[1].hasMarker == true)
    }

    @Test("The rail's field keeps the chapters whose notes or transcript match")
    func filteringTheRail() async throws {
        let model = try await loaded()

        model.railQuery = "Bélády"
        #expect(model.filteredChapters.map(\.blockNumber) == [1])

        // Only in the transcript, and only under the second card.
        model.railQuery = "Zeitfenster misst"
        #expect(model.filteredChapters.map(\.blockNumber) == [2])

        model.railQuery = "Bankiersalgorithmus"
        #expect(model.filteredChapters.isEmpty)

        model.railQuery = ""
        #expect(model.filteredChapters.count == 2)
    }

    @Test("One chapter is always the current one, and it is the first before anything has played")
    func currentChapter() async throws {
        let model = try await loaded()
        #expect(model.currentChapter?.blockNumber == 1)
    }

    // MARK: - The notes column

    @Test("The annotation the user typed sits under the card it falls in")
    func annotationInTheNotes() async throws {
        let model = try await loaded()

        #expect(model.noteItems.count == 3)
        #expect(model.markerCount == 1)
        if case let .annotation(found) = model.noteItems[2] {
            #expect(found.time == 3130)
        } else {
            Issue.record("the annotation belongs under the second card")
        }
    }

    /// The store numbers blocks from zero and everything else — a chapter row,
    /// a chat citation — counts from one.
    @Test("Stored blocks come back numbered from one")
    func blockNumbers() async throws {
        let model = try await loaded()
        #expect(model.blocks.map(\.number) == [1, 2])
    }

    // MARK: - Jumping

    @Test("A source chip citing the transcript brings the transcript tab forward")
    func chipOpensTheTranscript() async throws {
        let model = try await loaded()
        #expect(model.tab == .notes)

        model.follow(.transcript(3130))
        #expect(model.tab == .transcript)
    }

    @Test("A source chip citing a note stays on the notes")
    func noteChipStaysPut() async throws {
        let model = try await loaded()

        model.follow(.note(2))
        #expect(model.tab == .notes)
    }

    // MARK: - The find bar

    @Test("Typing in the find bar counts the matches in the loaded transcript")
    func findOverLoadedLines() async throws {
        let model = try await loaded()

        model.findQuery = "Working Set"
        #expect(model.find.count == 1)
        #expect(model.lineToScrollTo?.start == 3130)

        model.findQuery = ""
        #expect(model.find.count == 0)
        #expect(model.lineToScrollTo == nil)
    }

    // MARK: - The chat

    @Test("A recording that is still running cannot be asked about")
    func chatWhileRecording() async throws {
        let model = try await loaded(state: .recording)
        #expect(model.chatAvailability == .stillRecording)
    }

    @Test("A recording whose summary is still being written cannot be asked about either")
    func chatBeforeTheSummary() async throws {
        for state in [RecordingState.transcribing, .summarizing] {
            let model = try await loaded(state: state)
            #expect(model.chatAvailability == .summaryPending)
        }
    }

    @Test("A finished recording can be asked about")
    func chatWhenDone() async throws {
        #expect(try await loaded(state: .done).chatAvailability == .ready)
    }

    /// The rail says so rather than sending the question into a failure — and
    /// the question stays in the field, because the user has not asked it yet.
    @Test("Asking before the summary exists does nothing and keeps the question")
    func askingTooEarlyIsRefused() async throws {
        let chat = RecordingChat(
            backend: StubBackend(answers: ["""
                {"answer":"Inhaltlich derselbe Algorithmus.","references":["00:52:10"]}
                """]),
            model: "small",
            material: .init(notes: nil, transcript: [], isRecording: true)
        )
        let model = try await loaded(state: .recording, chat: chat)

        model.question = "Was ist der Unterschied zwischen Second Chance und Clock?"
        await model.ask()

        #expect(model.turns.isEmpty)
        #expect(model.question == "Was ist der Unterschied zwischen Second Chance und Clock?")
        #expect(model.chatFailure == nil)
    }

    @Test("Once the summary is written the question goes through and comes back cited")
    func askingWhenReady() async throws {
        let chat = RecordingChat(
            backend: StubBackend(answers: ["""
                {"answer":"Inhaltlich derselbe Algorithmus.","references":["00:52:10","Notiz 2"]}
                """]),
            model: "small",
            material: .init(notes: nil, transcript: [])
        )
        let model = try await loaded(state: .done, chat: chat)

        model.question = "Was ist der Unterschied zwischen Second Chance und Clock?"
        await model.ask()

        #expect(model.question.isEmpty)
        #expect(model.turns.count == 2)
        #expect(model.turns[0].author == .you)
        #expect(model.turns[1].author == .model)
        #expect(model.turns[1].references.contains(.transcript(3130)))
        #expect(model.turns[1].references.contains(.note(2)))
    }

    @Test("A recording with no chat at all is still a window that loads")
    func noChatConfigured() async throws {
        let model = try await loaded(chat: nil)

        model.question = "Frage"
        await model.ask()

        #expect(model.turns.isEmpty)
    }
}
