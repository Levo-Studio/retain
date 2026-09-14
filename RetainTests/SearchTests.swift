import Foundation
import GRDB
import Testing

@testable import Retain

@Suite("Search")
struct SearchTests {

    /// A term with one course, one recording, and a handful of German
    /// transcript lines in it — the shape every search test asks a question
    /// about.
    private func library(
        in database: RetainDatabase
    ) async throws -> (termID: Int64, recordingID: Int64) {
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)

        try await TranscriptRepository(database).replaceLines([
            StoreFixture.line(
                "Bevor wir zum nächsten Punkt kommen: Was heißt eigentlich, ein Prozess braucht Speicher?",
                at: 3014
            ),
            StoreFixture.line("Genau diese Menge nennen wir das Working Set.", at: 3130),
            StoreFixture.line("Über welches Zeitfenster misst man das?", at: 3168, speaker: .audience),
            StoreFixture.line("FIFO leidet unter der Bélády-Anomalie.", at: 660),
        ], for: recordingID)

        return (try #require(library.term.id), recordingID)
    }

    // MARK: - Finding and not finding

    @Test("A word that was said is found, with the recording and the second it was said at")
    func findsAWord() async throws {
        let database = try StoreFixture.database()
        let (termID, recordingID) = try await library(in: database)

        let hits = try await SearchRepository(database).search("Zeitfenster", in: termID)

        #expect(hits.count == 1)
        let hit = try #require(hits.first)
        #expect(hit.source == .transcript)
        #expect(hit.recordingID == recordingID)
        // Where the hit was said: the detail window opens at that line.
        #expect(hit.time == 3168)
        #expect(hit.text.contains("Zeitfenster"))
        #expect(hit.courseName == "Computer science")
        #expect(hit.recordingStartedAt == StoreFixture.instant(2026, 2, 7, 10, 15))
    }

    @Test("A word that was never said is not found")
    func doesNotFindWhatIsNotThere() async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)

        #expect(try await SearchRepository(database).search("Photosynthese", in: termID).isEmpty)
    }

    @Test("An empty query finds nothing rather than everything")
    func emptyQueryFindsNothing() async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)
        let repository = SearchRepository(database)

        #expect(try await repository.search("", in: termID).isEmpty)
        #expect(try await repository.search("   ", in: termID).isEmpty)
    }

    @Test("A word is found while it is still being typed")
    func findsAPrefix() async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)

        #expect(try await SearchRepository(database).search("Zeitfen", in: termID).count == 1)
    }

    @Test("Every word in the query has to be in the same line")
    func allWordsMustMatch() async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)
        let repository = SearchRepository(database)

        #expect(try await repository.search("Working Set", in: termID).count == 1)
        // "Working" is in one line and "Anomalie" in another, and no line has
        // both.
        #expect(try await repository.search("Working Anomalie", in: termID).isEmpty)
    }

    // MARK: - Scope

    @Test("Search stops at the edge of the term")
    func searchIsScopedToTheTerm() async throws {
        let database = try StoreFixture.database()
        let (winterID, _) = try await library(in: database)

        // The same sentence, one half-year later.
        let summer = try await StoreFixture.term(
            in: database,
            title: "Third year, summer",
            startsOn: StoreFixture.instant(2026, 4),
            endsOn: StoreFixture.instant(2026, 9)
        )
        let summerCourse = try await StoreFixture.course(
            in: database,
            term: summer,
            name: "Operating systems",
            color: .blue
        )
        let summerRecording = try await StoreFixture.recording(
            in: database,
            course: summerCourse,
            at: StoreFixture.instant(2026, 5, 4, 11, 0)
        )
        let summerRecordingID = try #require(summerRecording.id)
        try await TranscriptRepository(database).append(
            StoreFixture.line("Auch hier ist das Working Set gemeint.", at: 42),
            to: summerRecordingID
        )

        let repository = SearchRepository(database)
        let winterHits = try await repository.search("Working", in: winterID)
        #expect(winterHits.count == 1)
        #expect(winterHits.first?.recordingID != summerRecordingID)

        let summerHits = try await repository.search("Working", in: try #require(summer.id))
        #expect(summerHits.map(\.recordingID) == [summerRecordingID])
    }

    @Test("Two courses in the same term are both searched")
    func searchCoversEveryCourseInTheTerm() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let termID = try #require(library.term.id)

        let mathematics = try await StoreFixture.course(
            in: database,
            term: library.term,
            name: "Mathematics",
            color: .blue
        )
        let mathematicsRecording = try await StoreFixture.recording(
            in: database,
            course: mathematics,
            at: StoreFixture.instant(2026, 2, 6, 8, 0)
        )

        let transcript = TranscriptRepository(database)
        try await transcript.append(
            StoreFixture.line("Der Zwischenwertsatz sagt …", at: 10),
            to: try #require(library.recording.id)
        )
        try await transcript.append(
            StoreFixture.line("Der Zwischenwertsatz noch einmal …", at: 20),
            to: try #require(mathematicsRecording.id)
        )

        let hits = try await SearchRepository(database).search("Zwischenwertsatz", in: termID)
        #expect(hits.count == 2)
        #expect(Set(hits.map(\.courseName)) == ["Computer science", "Mathematics"])
    }

    // MARK: - Staying in step with the rows

    @Test("Correcting a line corrects what search finds")
    func searchFollowsAnEdit() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)
        let transcript = TranscriptRepository(database)
        let search = SearchRepository(database)

        var line = StoreFixture.line("Der Bankiersalgorithmus verhindert Verklemmungen.", at: 500)
        try await transcript.append(line, to: recordingID)
        #expect(try await search.search("Bankiersalgorithmus", in: termID).count == 1)

        line.text = "Der Bankieralgorithmus verhindert Verklemmungen."
        try await transcript.update(line, in: recordingID)

        #expect(try await search.search("Bankiersalgorithmus", in: termID).isEmpty)
        #expect(try await search.search("Bankieralgorithmus", in: termID).count == 1)
        // The rest of the line is still indexed, so the edit removed one word
        // and not the row.
        #expect(try await search.search("Verklemmungen", in: termID).count == 1)
    }

    @Test("A replaced transcript takes the old words out of search with it")
    func searchFollowsAReplacedTranscript() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)
        let transcript = TranscriptRepository(database)
        let search = SearchRepository(database)

        try await transcript.append(
            StoreFixture.line("Seitenersetzung nach Zufall", at: 12, isProvisional: true),
            to: recordingID
        )
        #expect(try await search.search("Zufall", in: termID).count == 1)

        try await transcript.replaceLines(
            [StoreFixture.line("Seitenersetzung nach Clock", at: 12)],
            for: recordingID
        )

        #expect(try await search.search("Zufall", in: termID).isEmpty)
        #expect(try await search.search("Clock", in: termID).count == 1)
    }

    @Test("A recording that is deleted stops being searchable")
    func searchFollowsADelete() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let termID = try #require(library.term.id)
        let recordingID = try #require(library.recording.id)

        try await TranscriptRepository(database).append(
            StoreFixture.line("Semaphoren und Monitore", at: 30),
            to: recordingID
        )
        #expect(try await SearchRepository(database).search("Semaphoren", in: termID).count == 1)

        try await database.writer.write { db in
            _ = try Recording.deleteOne(db, key: recordingID)
        }

        #expect(try await SearchRepository(database).search("Semaphoren", in: termID).isEmpty)
    }

    // MARK: - German, and what people actually type

    /// The case that breaks a naive tokenizer. Somebody looking for "Übung"
    /// types "ubung", and somebody looking for "Bélády" is not going to find
    /// the accents on a German keyboard at all.
    @Test("Umlauts and accents are found typed either way", arguments: [
        "Bélády", "belady", "Belady", "bélády",
    ])
    func findsAccentedWordsWithoutTheAccents(_ query: String) async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)

        #expect(try await SearchRepository(database).search(query, in: termID).count == 1)
    }

    @Test("A word with an umlaut is found with and without it", arguments: [
        "nächsten", "nachsten", "Nächsten", "NACHSTEN",
    ])
    func findsUmlautsEitherWay(_ query: String) async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)

        #expect(try await SearchRepository(database).search(query, in: termID).count == 1)
    }

    @Test("The sharp s is its own letter and is matched as typed")
    func findsTheSharpS() async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)

        #expect(try await SearchRepository(database).search("heißt", in: termID).count == 1)
    }

    /// Everything in here is FTS5 syntax. Reaching the parser, any one of them
    /// would be an error instead of a search.
    @Test("Punctuation in the query is a search, not a syntax error", arguments: [
        "Working-Set,",
        "\"Working Set\"",
        "Working Set!",
        "(Working, Set)",
        "»Working Set«",
        "Working — Set",
        "Working*",
        "Working^Set",
        "Menge: das Working Set.",
    ])
    func punctuationIsSearchedThrough(_ query: String) async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)

        #expect(try await SearchRepository(database).search(query, in: termID).count == 1)
    }

    /// The other half of the same guarantee: the syntax words do not reach the
    /// parser either, so "NOT" searches for the word "not" instead of inverting
    /// the query, and finds nothing because no line says it.
    @Test("An FTS5 operator typed into the field is a word", arguments: [
        "NOT Working",
        "Working OR Photosynthese",
        "Working AND Anomalie",
    ])
    func operatorsAreWords(_ query: String) async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)

        #expect(try await SearchRepository(database).search(query, in: termID).isEmpty)
    }

    @Test("A query that is nothing but punctuation finds nothing and throws nothing")
    func punctuationOnlyFindsNothing() async throws {
        let database = try StoreFixture.database()
        let (termID, _) = try await library(in: database)

        #expect(try await SearchRepository(database).search("*: - \" ()", in: termID).isEmpty)
    }

    // MARK: - Notes and annotations

    @Test("The notes are searched alongside the transcript")
    func findsAWordInTheNotes() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)

        try await NoteRepository(database).replaceBlocks([
            StoreFixture.noteBlock(
                """
                ## Working Set und Thrashing

                Passt das **Working Set** nicht in den Speicher, steigt die \
                Page-Fault-Rate.
                """,
                position: 0,
                startTime: 2940
            ),
        ], for: recordingID)

        let repository = SearchRepository(database)

        let bodyHits = try await repository.search("Page-Fault-Rate", in: termID)
        #expect(bodyHits.count == 1)
        #expect(bodyHits.first?.source == .note)
        #expect(bodyHits.first?.time == 2940)

        // The heading is in the same Markdown, so the chapters are findable
        // without a second column to hold them.
        #expect(try await repository.search("Thrashing", in: termID).count == 1)
    }

    /// The Markdown is indexed as written, and the punctuation that makes it
    /// Markdown does not turn into search terms or break the ones around it.
    @Test("Markdown syntax is not searched, the words in it are")
    func markdownSyntaxIsNotIndexed() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)

        try await NoteRepository(database).append(
            StoreFixture.noteBlock("## Clock\n\n- **Referenzbit** gesetzt, also *übersprungen*"),
            to: recordingID
        )

        let repository = SearchRepository(database)
        #expect(try await repository.search("Referenzbit", in: termID).count == 1)
        #expect(try await repository.search("übersprungen", in: termID).count == 1)
        #expect(try await repository.search("##", in: termID).isEmpty)
    }

    @Test("What the user typed during the lecture is findable afterwards")
    func findsAnAnnotation() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)

        try await TranscriptRepository(database).annotate(
            at: 3130,
            note: "Übungsblatt 5, Aufgabe 3 rechnet genau diesen Fall durch.",
            in: recordingID
        )

        let hits = try await SearchRepository(database).search("Aufgabe", in: termID)
        #expect(hits.count == 1)
        #expect(hits.first?.source == .annotation)
        #expect(hits.first?.time == 3130)
        #expect(hits.first?.text.hasPrefix("Übungsblatt") == true)
    }

    @Test("An annotation with no text is not a match for anything")
    func anEmptyAnnotationIsNotSearchable() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let termID = try #require(library.term.id)

        try await TranscriptRepository(database).annotate(at: 900, in: recordingID)

        #expect(try await SearchRepository(database).search("Working", in: termID).isEmpty)
    }

    @Test("A line, a note and an annotation that all match come back as three hits")
    func allThreeIndexesAreSearched() async throws {
        let database = try StoreFixture.database()
        let (termID, recordingID) = try await library(in: database)

        try await NoteRepository(database).append(
            StoreFixture.noteBlock(
                "## Working Set\n\nDie Menge der Seiten in einem Zeitfenster.",
                startTime: 3120
            ),
            to: recordingID
        )
        try await TranscriptRepository(database).annotate(
            at: 3140,
            note: "Zeitfenster: kommt in der Klausur",
            in: recordingID
        )

        let hits = try await SearchRepository(database).search("Zeitfenster", in: termID)
        #expect(hits.count == 3)
        #expect(Set(hits.map(\.source)) == [.transcript, .note, .annotation])
    }

    // MARK: - Order and size

    @Test("Hits come back newest recording first, earliest moment first inside one")
    func hitsAreOrderedByDateThenTime() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let termID = try #require(library.term.id)
        let transcript = TranscriptRepository(database)

        let older = try await StoreFixture.recording(
            in: database,
            course: library.course,
            at: StoreFixture.instant(2025, 11, 18, 9, 0)
        )
        // Later the same day as `older`, which is what the time of day is for.
        let newer = try await StoreFixture.recording(
            in: database,
            course: library.course,
            at: StoreFixture.instant(2025, 11, 18, 14, 30)
        )

        try await transcript.append(StoreFixture.line("Deadlock, spät", at: 900), to: try #require(newer.id))
        try await transcript.append(StoreFixture.line("Deadlock, früh", at: 100), to: try #require(newer.id))
        try await transcript.append(StoreFixture.line("Deadlock, davor", at: 500), to: try #require(older.id))

        let hits = try await SearchRepository(database).search("Deadlock", in: termID)
        #expect(hits.map(\.time) == [100, 900, 500])
        #expect(hits.first?.recordingID == newer.id)
        #expect(hits.last?.recordingID == older.id)
    }

    @Test("A term of recordings does not come back all at once")
    func theLimitIsHonoured() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let termID = try #require(library.term.id)
        let recordingID = try #require(library.recording.id)

        try await TranscriptRepository(database).replaceLines(
            (0..<200).map { StoreFixture.line("Paging, Zeile \($0)", at: Double($0) * 12) },
            for: recordingID
        )

        #expect(try await SearchRepository(database).search("Paging", in: termID, limit: 25).count == 25)
        #expect(try await SearchRepository(database).search("Paging", in: termID).count == 50)
    }
}
