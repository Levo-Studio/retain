import Foundation
import GRDB
import Testing

@testable import Retain

@Suite("Transcript store")
struct TranscriptStoreTests {

    // MARK: - Lines

    @Test("A line comes back with its times, its speaker and its identity")
    func aLineRoundTrips() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = TranscriptRepository(database)

        let line = StoreFixture.line(
            "Über welches Zeitfenster misst man das?",
            at: 3168,
            to: 3172.5,
            speaker: .audience
        )
        try await repository.append(line, to: recordingID)

        let read = try #require(try await repository.lines(for: recordingID).first)
        #expect(read.id == line.id)
        #expect(read.start == 3168)
        #expect(read.end == 3172.5)
        #expect(read.text == "Über welches Zeitfenster misst man das?")
        #expect(read.speaker == .audience)
        #expect(read.isProvisional == false)
    }

    @Test("Every speaker survives the round trip", arguments: [
        SpeakerRole.lecturer,
        SpeakerRole.audience,
        SpeakerRole.unknown,
    ])
    func speakersRoundTrip(_ speaker: SpeakerRole) async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = TranscriptRepository(database)

        try await repository.append(StoreFixture.line("Eine Zeile", at: 1, speaker: speaker), to: recordingID)
        #expect(try await repository.lines(for: recordingID).first?.speaker == speaker)
    }

    @Test("Lines come back in time order whatever order they arrived in")
    func linesComeBackInTimeOrder() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = TranscriptRepository(database)

        for start in [40.0, 10.0, 30.0, 20.0] {
            try await repository.append(StoreFixture.line("At \(Int(start))", at: start), to: recordingID)
        }

        #expect(try await repository.lines(for: recordingID).map(\.start) == [10, 20, 30, 40])
    }

    /// A 90-minute lecture is a few hundred lines, and every one of them is
    /// written in the one transaction the batch pass ends with.
    @Test("A lecture's worth of lines goes in at once and comes back in order")
    func aWholeLectureRoundTrips() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = TranscriptRepository(database)

        let lines = (0..<600).map { index in
            StoreFixture.line(
                "Line number \(index) of the lecture",
                at: Double(index) * 9,
                to: Double(index) * 9 + 8,
                speaker: index.isMultiple(of: 20) ? .audience : .lecturer
            )
        }
        try await repository.replaceLines(lines, for: recordingID)

        let read = try await repository.lines(for: recordingID)
        #expect(read.count == 600)
        #expect(read.map(\.start) == lines.map(\.start))
        #expect(read.map(\.text) == lines.map(\.text))
        #expect(read.map(\.id) == lines.map(\.id))
        #expect(read.filter { $0.speaker == .audience }.count == 30)
    }

    @Test("The batch transcript replaces the live one instead of joining it")
    func theBatchPassReplacesTheLivePass() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = TranscriptRepository(database)

        for index in 0..<5 {
            try await repository.append(
                StoreFixture.line("Live line \(index)", at: Double(index) * 10, isProvisional: true),
                to: recordingID
            )
        }
        #expect(try await repository.lines(for: recordingID).allSatisfy(\.isProvisional))

        try await repository.replaceLines(
            (0..<7).map { StoreFixture.line("Final line \($0)", at: Double($0) * 7) },
            for: recordingID
        )

        let read = try await repository.lines(for: recordingID)
        #expect(read.count == 7)
        #expect(read.allSatisfy { !$0.isProvisional })
        #expect(read.allSatisfy { !$0.text.hasPrefix("Live") })
    }

    @Test("One recording's transcript leaves another's alone")
    func transcriptsAreScopedToTheirRecording() async throws {
        let database = try StoreFixture.database()
        let library = try await StoreFixture.library(in: database)
        let other = try await StoreFixture.recording(
            in: database,
            course: library.course,
            at: StoreFixture.instant(2026, 2, 7, 14, 30)
        )
        let repository = TranscriptRepository(database)

        let recordingID = try #require(library.recording.id)
        let otherID = try #require(other.id)

        try await repository.append(StoreFixture.line("First recording", at: 1), to: recordingID)
        try await repository.append(StoreFixture.line("Second recording", at: 1), to: otherID)
        try await repository.replaceLines([StoreFixture.line("Rewritten", at: 2)], for: recordingID)

        #expect(try await repository.lines(for: recordingID).map(\.text) == ["Rewritten"])
        #expect(try await repository.lines(for: otherID).map(\.text) == ["Second recording"])
    }

    @Test("A line can be corrected in place, and keeps its identity")
    func aLineCanBeCorrected() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = TranscriptRepository(database)

        var line = StoreFixture.line("Second Chanse prüft das Referenzbit", at: 1380)
        try await repository.append(line, to: recordingID)

        line.text = "Second Chance prüft das Referenzbit"
        line.speaker = .lecturer
        try await repository.update(line, in: recordingID)

        let read = try await repository.lines(for: recordingID)
        #expect(read.count == 1)
        #expect(read.first?.text == "Second Chance prüft das Referenzbit")
        #expect(read.first?.id == line.id)
    }

    // MARK: - Annotations

    @Test("Annotations come back in time order, with and without text")
    func annotationsRoundTrip() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = TranscriptRepository(database)

        try await repository.annotate(at: 3130, note: "Exercise sheet 5, question 3", in: recordingID)
        try await repository.annotate(at: 280, in: recordingID)

        let annotations = try await repository.annotations(for: recordingID)
        #expect(annotations.map(\.time) == [280, 3130])
        #expect(annotations.first?.note == nil)
        #expect(annotations.last?.note == "Exercise sheet 5, question 3")
    }

    // MARK: - Notes

    @Test("Note blocks come back in reading order, as the Markdown they were written as")
    func noteBlocksRoundTrip() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = NoteRepository(database)

        let second = """
            ## Working Set und Thrashing

            Das **Working Set** ist die Menge der Seiten, die ein Prozess in einem \
            Zeitfenster anfasst.
            """
        let first = """
            ## Wann eine Seite verdrängt werden darf

            - FIFO ist billig, leidet aber unter der Bélády-Anomalie
            - Second Chance prüft das Referenzbit
            """

        try await repository.replaceBlocks(
            [
                StoreFixture.noteBlock(second, position: 1, startTime: 2940),
                StoreFixture.noteBlock(first, position: 0, startTime: 240),
            ],
            for: recordingID
        )

        let blocks = try await repository.blocks(for: recordingID)
        #expect(blocks.map(\.position) == [0, 1])
        #expect(blocks.first?.markdown == first)
        #expect(blocks.first?.startTime == 240)
        #expect(blocks.allSatisfy { $0.recordingID == recordingID })
    }

    @Test("Writing the notes again replaces them rather than doubling them")
    func replacingNotesClearsTheOldOnes() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = NoteRepository(database)

        try await repository.append(
            StoreFixture.noteBlock("## Block 1\n\nWritten while the lecture ran."),
            to: recordingID
        )
        try await repository.replaceBlocks(
            [StoreFixture.noteBlock("## Chapter 1\n\nWritten by the reduce afterwards.")],
            for: recordingID
        )

        let blocks = try await repository.blocks(for: recordingID)
        #expect(blocks.count == 1)
        #expect(blocks.first?.markdown.hasPrefix("## Chapter 1") == true)
    }

    // MARK: - Highlights

    @Test("A highlight marks a range of one block and comes back with it")
    func highlightsRoundTrip() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = NoteRepository(database)

        let markdown = "## Working Set\n\nDie Menge der Seiten in einem Zeitfenster."
        let block = try await repository.append(
            StoreFixture.noteBlock(markdown, startTime: 2940),
            to: recordingID
        )

        // The range the interface would hand over for "Menge der Seiten",
        // counted the way the column stores it.
        let start = try #require(markdown.utf8.firstRange(of: Array("Menge".utf8))?.lowerBound)
        let startOffset = markdown.utf8.distance(from: markdown.utf8.startIndex, to: start)
        // A fixed instant, because SQLite keeps a date to the millisecond and
        // `.now` has more than that: the round trip is lossless only for a
        // time that was not made up on the spot.
        let marked = StoreFixture.instant(2026, 2, 7, 18, 30)
        let highlight = try await repository.highlight(
            block,
            from: startOffset,
            to: startOffset + 16,
            at: marked
        )

        let read = try await repository.highlights(for: recordingID)
        #expect(read.count == 1)
        #expect(read.first == highlight)
        #expect(read.first?.createdAt == marked)
        #expect(read.first?.noteBlockID == block.id)
        #expect(read.first?.recordingID == recordingID)

        // And the range still points at what was marked.
        let bytes = Array(markdown.utf8)[highlight.startOffset..<highlight.endOffset]
        #expect(String(decoding: bytes, as: UTF8.self) == "Menge der Seiten")
    }

    @Test("Highlights come back block by block, in reading order inside each")
    func highlightsAreOrdered() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = NoteRepository(database)

        let first = try await repository.append(
            StoreFixture.noteBlock("## One\n\nAlpha beta gamma delta.", position: 0),
            to: recordingID
        )
        let second = try await repository.append(
            StoreFixture.noteBlock("## Two\n\nEpsilon zeta eta theta.", position: 1),
            to: recordingID
        )

        try await repository.highlight(second, from: 10, to: 17)
        try await repository.highlight(first, from: 20, to: 25)
        try await repository.highlight(first, from: 9, to: 14)

        let inFirst = try await repository.highlights(inBlock: try #require(first.id))
        #expect(inFirst.map(\.startOffset) == [9, 20])

        let all = try await repository.highlights(for: recordingID)
        #expect(all.map(\.noteBlockID) == [first.id, first.id, second.id])
    }

    @Test("A highlight can be taken back off without touching the notes")
    func aHighlightCanBeRemoved() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = NoteRepository(database)

        let block = try await repository.append(
            StoreFixture.noteBlock("## One\n\nAlpha beta gamma."),
            to: recordingID
        )
        let highlight = try await repository.highlight(block, from: 9, to: 14)

        try await repository.removeHighlight(try #require(highlight.id))

        #expect(try await repository.highlights(for: recordingID).isEmpty)
        #expect(try await repository.blocks(for: recordingID).count == 1)
    }

    @Test("A highlight cannot be filed against a block that was never written")
    func highlightNeedsAStoredBlock() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = NoteRepository(database)

        await #expect(throws: RetainDatabaseError.unsavedRow) {
            try await repository.highlight(
                StoreFixture.noteBlock("## Not saved\n\nNothing."),
                from: 0,
                to: 3
            )
        }
        #expect(try await repository.highlights(for: recordingID).isEmpty)
    }

    /// The consequence of re-summarising a recording somebody has marked up.
    /// It is written down as a test because it is the behaviour, not because it
    /// is wanted: a byte range into Markdown the model rewrote from scratch has
    /// nothing left to point at.
    @Test("Rewriting the notes takes the highlights in them with it")
    func replacingNotesDropsHighlights() async throws {
        let database = try StoreFixture.database()
        let recordingID = try #require(try await StoreFixture.library(in: database).recording.id)
        let repository = NoteRepository(database)

        let block = try await repository.append(
            StoreFixture.noteBlock("## Working Set\n\nDie Menge der Seiten."),
            to: recordingID
        )
        try await repository.highlight(block, from: 17, to: 21)

        try await repository.replaceBlocks(
            [StoreFixture.noteBlock("## Working Set\n\nDie Menge der Seiten in einem Fenster.")],
            for: recordingID
        )

        #expect(try await repository.highlights(for: recordingID).isEmpty)
    }
}
