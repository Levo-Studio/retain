import Foundation
import Testing

@testable import Retain

private func card(_ number: Int, _ heading: String, start: TimeInterval) -> NoteBlock {
    NoteBlock(
        number: number,
        markdown: "## \(heading)\nAbsatz über \(heading).",
        start: start,
        end: start + 180
    )
}

private let notes = RecordingNotes(
    topic: "Virtueller Speicher und Paging",
    markdown: "## Adressräume\nAbsatz.",
    blocks: [card(1, "Adressräume", start: 0), card(2, "Der TLB", start: 180)]
)

private let transcript = [
    TranscriptLine(start: 0, end: 8, text: "Der virtuelle Adressraum ist zunächst nur eine Abmachung."),
    TranscriptLine(start: 8, end: 16, text: "Die Seitentabelle bildet virtuelle Seiten auf physische Kacheln ab."),
    TranscriptLine(start: 16, end: 24, text: "Der TLB hält die letzten Übersetzungen."),
]

private let answerReply = """
    {"answer":"Der TLB ist ein Cache für Übersetzungen.","references":["00:00:16","Notiz 2"]}
    """

// MARK: - When it can be used

@Suite("Chat availability")
struct ChatAvailabilityTests {

    /// A state rather than an error: the rail is on screen while the recording
    /// is still running, and it has to say why it cannot be used yet.
    @Test("The three states")
    func theTable() {
        #expect(ChatAvailability.of(isRecording: true, hasNotes: false) == .stillRecording)
        #expect(ChatAvailability.of(isRecording: true, hasNotes: true) == .stillRecording)
        #expect(ChatAvailability.of(isRecording: false, hasNotes: false) == .summaryPending)
        #expect(ChatAvailability.of(isRecording: false, hasNotes: true) == .ready)
    }

    @Test("A recording that is still running cannot be asked about")
    func askingTooEarlyFails() async throws {
        let chat = RecordingChat(
            backend: StubBackend(answers: [answerReply]),
            model: "small",
            material: .init(notes: notes, transcript: transcript, isRecording: true)
        )

        #expect(await chat.availability == .stillRecording)
        await #expect(throws: SummarizationError.chatNotReady(.stillRecording)) {
            try await chat.ask("Was ist der TLB?")
        }
    }

    @Test("A recording with no summary yet cannot be asked about either")
    func askingBeforeTheSummaryFails() async throws {
        let chat = RecordingChat(
            backend: StubBackend(answers: [answerReply]),
            model: "small",
            material: .init(notes: nil, transcript: transcript)
        )

        #expect(await chat.availability == .summaryPending)
        await #expect(throws: SummarizationError.chatNotReady(.summaryPending)) {
            try await chat.ask("Was ist der TLB?")
        }
    }

    @Test("The summary landing makes the chat usable")
    func updatingMaterialOpensTheChat() async throws {
        let chat = RecordingChat(
            backend: StubBackend(answers: [answerReply]),
            model: "small",
            material: .init(notes: nil, transcript: transcript)
        )

        await chat.update(.init(notes: notes, transcript: transcript))
        #expect(await chat.availability == .ready)
    }
}

// MARK: - Asking

@Suite("Recording chat")
struct RecordingChatTests {

    private func chat(_ backend: StubBackend) -> RecordingChat {
        RecordingChat(
            backend: backend,
            model: "small",
            material: .init(notes: notes, transcript: transcript)
        )
    }

    @Test("An answer comes back with its sources")
    func answersCarryReferences() async throws {
        let conversation = chat(StubBackend(answers: [answerReply]))
        let answer = try await conversation.ask("Was ist der TLB?")

        #expect(answer.author == .model)
        #expect(answer.text == "Der TLB ist ein Cache für Übersetzungen.")
        #expect(answer.references == [.transcript(16), .note(2)])
    }

    @Test("Both turns end up in the rail, question first")
    func bothTurnsAreKept() async throws {
        let conversation = chat(StubBackend(answers: [answerReply]))
        _ = try await conversation.ask("Was ist der TLB?")

        let turns = await conversation.turns
        #expect(turns.count == 2)
        #expect(turns[0].author == .you)
        #expect(turns[0].text == "Was ist der TLB?")
        #expect(turns[1].author == .model)
    }

    /// A question that vanished because the server was down would have to be
    /// typed again.
    @Test("A question survives an answer that never arrives")
    func questionsSurviveAFailure() async throws {
        let conversation = chat(StubBackend(answers: []))

        await #expect(throws: SummarizationError.unreachable) {
            try await conversation.ask("Was ist der TLB?")
        }

        let turns = await conversation.turns
        #expect(turns.count == 1)
        #expect(turns[0].author == .you)
    }

    @Test("An empty question is not a question")
    func emptyQuestionsAreRefused() async throws {
        let conversation = chat(StubBackend(answers: [answerReply]))

        await #expect(throws: SummarizationError.emptyReply) {
            try await conversation.ask("   ")
        }
        #expect(await conversation.turns.isEmpty)
    }

    /// Board 04: "Das Modell sieht Notizen und Transkript."
    @Test("The model is shown the notes and the transcript")
    func theModelSeesBoth() async throws {
        let backend = StubBackend(answers: [answerReply])
        _ = try await chat(backend).ask("Was ist der TLB?")

        let material = try #require(backend.conversations.first?.messages.first { $0.role == .system && $0.content.contains("Notes for this recording") })

        #expect(material.content.contains("Notiz 1"))
        #expect(material.content.contains("Adressräume"))
        #expect(material.content.contains("Der TLB hält die letzten Übersetzungen."))
    }

    @Test("Earlier turns travel with a follow-up")
    func historyIsCarried() async throws {
        let backend = StubBackend(answers: [answerReply, answerReply])
        let conversation = chat(backend)

        _ = try await conversation.ask("Was ist der TLB?")
        _ = try await conversation.ask("Und warum ist er schnell?")

        let second = try #require(backend.conversations.last)
        #expect(second.messages.contains { $0.role == .user && $0.content == "Was ist der TLB?" })
        #expect(second.messages.last?.content == "Und warum ist er schnell?")
    }
}

// MARK: - Parsing what the model cites

@Suite("Chat references")
struct ChatReferenceTests {

    @Test("Both spellings the model was given")
    func theTwoSpellings() {
        #expect(ChatAnswering.reference(from: "00:38:20") == .transcript(2_300))
        #expect(ChatAnswering.reference(from: "38:20") == .transcript(2_300))
        #expect(ChatAnswering.reference(from: "Notiz 3") == .note(3))
    }

    /// Half of an English-instructed model's vocabulary is English, and the
    /// transcript was shown to it in square brackets.
    @Test("And the spellings it uses anyway")
    func theSpellingsItUsesAnyway() {
        #expect(ChatAnswering.reference(from: "[00:12:00]") == .transcript(720))
        #expect(ChatAnswering.reference(from: "Note 2") == .note(2))
        #expect(ChatAnswering.reference(from: "Block 4") == .note(4))
        #expect(ChatAnswering.reference(from: " notiz 1 ") == .note(1))
    }

    @Test("Anything that is not a jump target is not a chip")
    func prosIsNotAReference() {
        #expect(ChatAnswering.reference(from: "ungefähr in der Mitte") == nil)
        #expect(ChatAnswering.reference(from: "") == nil)
        #expect(ChatAnswering.reference(from: "Notiz") == nil)
        #expect(ChatAnswering.reference(from: "12") == nil)
    }

    /// The commonest hallucination in a citation: a model that cannot find a
    /// source makes a plausible-looking time up.
    @Test("A source that cannot exist is dropped rather than drawn")
    func impossibleReferencesAreDropped() {
        let answer = ChatAnswering.Answer(
            answer: "Antwort.",
            references: ["00:10", "99:00:00", "Notiz 1", "Notiz 9", "Quatsch"]
        )

        let turn = ChatAnswering.turn(
            from: answer,
            blocks: [card(1, "Adressräume", start: 0)],
            duration: 600
        )

        #expect(turn.references == [.transcript(10), .note(1)])
    }

    @Test("The same source cited twice is one chip")
    func duplicatesAreCollapsed() {
        let answer = ChatAnswering.Answer(answer: "Antwort.", references: ["Notiz 1", "Note 1"])
        let turn = ChatAnswering.turn(from: answer, blocks: [card(1, "Eins", start: 0)], duration: nil)

        #expect(turn.references == [.note(1)])
    }

    @Test("An answer with no sources is an answer with no chips")
    func referencesMayBeEmpty() throws {
        let decoded = try StructuredJSON.decode(
            ChatAnswering.Answer.self,
            from: "{\"answer\":\"Dazu steht nichts im Transkript.\"}"
        )

        #expect(decoded.references.isEmpty)
        #expect(ChatAnswering.turn(from: decoded, blocks: [], duration: nil).references.isEmpty)
    }

    @Test("The prompt forbids answering from anything but this recording")
    func promptIsGrounded() {
        #expect(ChatAnswering.systemPrompt.contains("only from the notes and the transcript"))
        #expect(ChatAnswering.systemPrompt.contains("German"))
        #expect(ChatAnswering.systemPrompt.contains("Notiz 3"))
    }
}

// MARK: - Picking the part of the transcript that matters

@Suite("Transcript retrieval")
struct TranscriptRetrievalTests {

    private func line(_ index: Int, _ text: String) -> TranscriptLine {
        TranscriptLine(start: Double(index) * 10, end: Double(index) * 10 + 10, text: text)
    }

    private var recording: [TranscriptLine] {
        (0..<200).map { index in
            switch index {
            case 40: line(index, "Die Bélády-Anomalie tritt bei FIFO auf und bei sonst nichts.")
            case 120: line(index, "Das Working Set ist die Menge der Seiten in einem Zeitfenster.")
            default: line(index, "Ein gewöhnlicher Satz über irgendetwas anderes, Nummer \(index).")
            }
        }
    }

    @Test("A transcript that fits is not touched")
    func shortTranscriptsComeBackWhole() {
        let short = (0..<5).map { line($0, "Ein kurzer Satz.") }
        #expect(TranscriptRetrieval.excerpt(of: short, for: "Worum ging es?", tokenBudget: 10_000) == short)
    }

    @Test("Nothing in, nothing out")
    func emptyGivesNothing() {
        #expect(TranscriptRetrieval.excerpt(of: [], for: "Frage", tokenBudget: 1_000).isEmpty)
        #expect(TranscriptRetrieval.excerpt(of: recording, for: "Frage", tokenBudget: 0).isEmpty)
    }

    /// The whole point: the answer is at minute twenty, and truncating would
    /// have answered from minute one.
    @Test("The lines the question is about are the lines that come back")
    func theRelevantLinesAreChosen() {
        let chosen = TranscriptRetrieval.excerpt(
            of: recording,
            for: "Was war noch mal die Bélády-Anomalie?",
            tokenBudget: 200
        )

        #expect(chosen.contains { $0.text.contains("Bélády-Anomalie") })
        #expect(!chosen.isEmpty)
    }

    @Test("A hit brings its neighbours along for context")
    func hitsCarryTheirContext() {
        let chosen = TranscriptRetrieval.excerpt(
            of: recording,
            for: "Working Set",
            tokenBudget: 400
        )

        let numbers = chosen.map(\.start)
        #expect(numbers.contains(1_200))
        #expect(numbers.contains(1_190))
        #expect(numbers.contains(1_210))
    }

    @Test("What comes back is in time order")
    func excerptsAreOrdered() {
        let chosen = TranscriptRetrieval.excerpt(
            of: recording,
            for: "Bélády-Anomalie und Working Set",
            tokenBudget: 600
        )

        #expect(chosen == chosen.sorted { $0.start < $1.start })
    }

    @Test("The budget is kept")
    func theBudgetIsKept() {
        for budget in [80, 200, 500, 1_500] {
            let chosen = TranscriptRetrieval.excerpt(of: recording, for: "Working Set", tokenBudget: budget)
            let used = chosen.reduce(0) { $0 + TokenBudget.estimatedTokens(in: $1.text) }
            #expect(used <= budget)
        }
    }

    /// "Worum ging es hier eigentlich" matches nothing in particular, and the
    /// honest answer covers the whole recording rather than its first minutes.
    @Test("A question that matches nothing gets a sample of the whole recording")
    func unmatchedQuestionsSampleEvenly() {
        let chosen = TranscriptRetrieval.excerpt(
            of: recording,
            for: "Worum ging es hier eigentlich?",
            tokenBudget: 300
        )

        #expect(!chosen.isEmpty)
        #expect(chosen.count < recording.count)
        // The sample reaches the end of the recording, not only its opening.
        #expect((chosen.last?.start ?? 0) > 1_000)
    }

    @Test("Words too common to tell anything apart are not matched on")
    func stopWordsAreIgnored() {
        #expect(TranscriptRetrieval.terms(in: "Was ist denn nun das Working Set?") == ["working"])
        #expect(TranscriptRetrieval.terms(in: "Und warum?").isEmpty)
    }

    /// German inflects and compounds: a question about the Seitentabelle has to
    /// match a line that says Seitentabellen.
    @Test("A term matches the word it was folded into")
    func matchingSurvivesGerman() {
        let terms = TranscriptRetrieval.terms(in: "Wozu dient die Seitentabelle?")

        #expect(TranscriptRetrieval.score("Die Seitentabellen liegen im Speicher.", against: terms) == 1)
        #expect(TranscriptRetrieval.score("Nichts davon hier.", against: terms) == 0)
    }

    @Test("A line matching two of the question's words beats one matching one")
    func scoresAreCounts() {
        // "Set" is three letters and drops out with the rest of the short
        // words; "und" is a stop word. Two terms are left.
        let terms = TranscriptRetrieval.terms(in: "Working Set und Thrashing?")
        #expect(terms == ["working", "thrashing"])

        #expect(TranscriptRetrieval.score("Working Set und Thrashing hängen zusammen.", against: terms) == 2)
        #expect(TranscriptRetrieval.score("Nur Thrashing.", against: terms) == 1)
    }
}
