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

    /// The model, and the store behind it — for the tests that write to the
    /// store directly, or read it back to check what the model wrote.
    private func loaded(
        state: RecordingState = .done,
        cards: [String] = [firstCard, secondCard],
        annotations: [(TimeInterval, String)] = [(3130, "Übungsblatt 5, Aufgabe 3 rechnet genau diesen Fall durch.")],
        chat: RecordingChat? = nil
    ) async throws -> RecordingDetailModel {
        try await loadedWithStore(state: state, cards: cards, annotations: annotations, chat: chat).model
    }

    private func loadedWithStore(
        state: RecordingState = .done,
        cards: [String] = [firstCard, secondCard],
        annotations: [(TimeInterval, String)] = [(3130, "Übungsblatt 5, Aufgabe 3 rechnet genau diesen Fall durch.")],
        chat: RecordingChat? = nil
    ) async throws -> (model: RecordingDetailModel, database: RetainDatabase) {
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
        return (model, database)
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

    @Test("One chapter is always the current one, and it is the first before the window is pointed anywhere")
    func currentChapter() async throws {
        let model = try await loaded()
        #expect(model.currentChapter?.blockNumber == 1)
    }

    @Test("The accent rule follows the chapter the window was last taken to")
    func currentChapterFollows() async throws {
        let model = try await loaded()

        model.show(chapter: try #require(model.chapters.last))
        #expect(model.currentChapter?.blockNumber == 2)
    }

    // MARK: - The notes column

    /// The column is the model's cards and nothing else. What the student typed
    /// is still counted, still flags its chapter, and reaches the notes through
    /// the model rather than beside it — see `NotesComposition`.
    @Test("The notes column is the cards, and what the user typed is not parked in it")
    func theColumnIsTheCards() async throws {
        let model = try await loaded()

        #expect(model.noteItems == model.blocks.map(NoteItem.block))
        #expect(model.markerCount == 1)
        #expect(model.markers.contains { $0.time == 3130 })
    }

    // MARK: - Editing the recording itself

    /// The topic the model guessed is the recording's name in the library, in
    /// the search and at the top of this window. It used to be unchangeable.
    @Test("The recording can be renamed, and the new name is what is stored")
    func renaming() async throws {
        let (model, database) = try await loadedWithStore()
        let id = try #require(model.recording.id)

        await model.rename(to: "  Seitenersetzung, zweiter Anlauf  ")

        #expect(model.recording.topic == "Seitenersetzung, zweiter Anlauf")
        let stored = try await LibraryRepository(database).recording(id)
        #expect(stored?.topic == "Seitenersetzung, zweiter Anlauf")
    }

    /// An empty name is not a name. Storing a blank one would put a recording
    /// with no visible title in the library, where a recording with no topic
    /// shows when it happened instead.
    @Test("An empty name clears the topic rather than storing a blank one")
    func renamingToNothing() async throws {
        let model = try await loaded()

        await model.rename(to: "   ")

        #expect(model.recording.topic == nil)
        #expect(RecordingPresentation.title(of: model.recording) != "")
    }

    /// Clicking into the name and clicking straight back out is the ordinary
    /// accident, and it has to cost nothing — the field saves on losing focus,
    /// so an unchanged name reaching `rename` is the common case and not the
    /// odd one.
    @Test("Saving an unchanged name changes nothing")
    func renamingToTheSameName() async throws {
        let (model, database) = try await loadedWithStore()
        let id = try #require(model.recording.id)
        let before = try #require(model.recording.topic)

        await model.rename(to: before)

        #expect(model.recording.topic == before)
        let stored = try await LibraryRepository(database).recording(id)
        #expect(stored?.topic == before)
    }

    @Test("The recording moves to another course in the same term")
    func moving() async throws {
        let (model, database) = try await loadedWithStore()
        let id = try #require(model.recording.id)
        let term = try #require(model.term)
        let other = try await StoreFixture.course(in: database, term: term, name: "Biologie")

        await model.load()
        #expect(model.coursesInTerm.count == 2)

        await model.move(to: other)

        #expect(model.course?.id == other.id)
        let stored = try await LibraryRepository(database).recording(id)
        #expect(stored?.courseID == other.id)
        // The half-year does not move with it.
        #expect(stored?.termID == term.id)
    }

    /// A recording belongs to the half-year it was recorded in, and that is not
    /// something this window corrects. A course from another term would be a
    /// pairing the library has no row for.
    @Test("A course from another term is refused")
    func movingOutsideTheTerm() async throws {
        let (model, database) = try await loadedWithStore()
        let before = try #require(model.course?.id)
        let otherTerm = try await StoreFixture.term(in: database, title: "Third year, summer", isCurrent: false)
        let elsewhere = try await StoreFixture.course(in: database, term: otherTerm, name: "Chemie")

        await model.load()
        await model.move(to: elsewhere)

        #expect(model.course?.id == before)
    }

    /// The store numbers blocks from zero and everything else — a chapter row,
    /// a chat citation — counts from one.
    @Test("Stored blocks come back numbered from one")
    func blockNumbers() async throws {
        let model = try await loaded()
        #expect(model.blocks.map(\.number) == [1, 2])
    }

    // MARK: - Moving around the window

    /// The recording this whole suite loads has no audio: it was transcribed,
    /// and the file went with the transcript being written. That is the
    /// ordinary state of every finished recording, so every test above this one
    /// is also the test that a window with no audio still has everything in it.
    @Test("A recording whose audio is gone still has its notes, its transcript and its timestamps")
    func nothingNeedsTheAudio() async throws {
        let model = try await loaded()

        #expect(model.recording.filename == nil)
        #expect(model.blocks.count == 2)
        #expect(model.lines.count == 2)
        #expect(model.annotations.count == 1)
        #expect(model.chapters.map(\.time) == [240, 2940])
        #expect(model.lines.map(\.start) == [3130, 3168])
        #expect(model.annotations.map(\.time) == [3130])
        #expect(RetainTimeFormat.clock(model.lines[0].start) == "00:52:10")
    }

    @Test("A chapter row brings the notes forward at its block")
    func chapterRowRevealsItsBlock() async throws {
        let model = try await loaded()
        model.tab = .transcript

        model.show(chapter: try #require(model.chapters.last))

        #expect(model.tab == .notes)
        #expect(model.reveal?.target == .block(2))
    }

    /// `onChange` fires on a changed value, so two clicks that produced the
    /// same request would scroll once and then look broken.
    @Test("The same chapter clicked twice is asked for twice")
    func chapterRowAsksAgain() async throws {
        let model = try await loaded()
        let chapter = try #require(model.chapters.first)

        model.show(chapter: chapter)
        let first = try #require(model.reveal)
        model.show(chapter: chapter)

        #expect(model.reveal != first)
        #expect(model.reveal?.target == first.target)
    }

    @Test("A source chip citing the transcript brings the transcript tab forward, at the line")
    func chipOpensTheTranscript() async throws {
        let model = try await loaded()
        #expect(model.tab == .notes)

        model.follow(.transcript(3130))

        #expect(model.tab == .transcript)
        #expect(model.reveal?.target == .line(model.lines[0].id))
    }

    @Test("A source chip citing a note stays on the notes, at that card")
    func noteChipStaysPut() async throws {
        let model = try await loaded()

        model.follow(.note(2))

        #expect(model.tab == .notes)
        #expect(model.reveal?.target == .block(2))
    }

    @Test("A chip citing a note that is not there any more does nothing at all")
    func chipForAMissingNote() async throws {
        let model = try await loaded()

        model.follow(.note(9))

        #expect(model.reveal == nil)
        #expect(model.tab == .notes)
    }

    /// A search hit in the library carries the second it matched at, and the
    /// window it opens is a window on a sentence.
    @Test("A search hit opens the transcript at the line it matched in")
    func searchHitOpensItsLine() async throws {
        let model = try await loaded()

        model.seek(to: 3170)

        #expect(model.tab == .transcript)
        #expect(model.reveal?.target == .line(model.lines[1].id))
        // The rail follows the reader to the chapter that line falls under.
        #expect(model.currentChapter?.blockNumber == 2)
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
