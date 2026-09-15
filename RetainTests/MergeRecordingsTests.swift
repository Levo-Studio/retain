import Foundation
import Testing

@testable import Retain

/// One lesson recorded as two, joined back into one.
///
/// The microphone gets stopped at a break and started again afterwards, and the
/// library then holds two half-lectures whose notes are each written from half
/// the material. Merging is what makes them the lesson again.
@MainActor
@Suite("Merging recordings")
struct MergeRecordingsTests {

    private func twoHalves() async throws -> (
        database: RetainDatabase,
        first: Recording,
        second: Recording
    ) {
        let database = try StoreFixture.database()
        let term = try await StoreFixture.term(in: database, isCurrent: true)
        let course = try await StoreFixture.course(in: database, term: term)

        var first = try await StoreFixture.recording(
            in: database,
            course: course,
            term: term,
            at: StoreFixture.instant(2026, 2, 7, 10, 15)
        )
        first.duration = 600
        first.state = .done
        first.topic = "Erste Hälfte"
        try await LibraryRepository(database).save(first)

        var second = try await StoreFixture.recording(
            in: database,
            course: course,
            term: term,
            at: StoreFixture.instant(2026, 2, 7, 10, 40)
        )
        second.duration = 300
        second.state = .done
        second.topic = "Zweite Hälfte"
        try await LibraryRepository(database).save(second)

        let transcripts = TranscriptRepository(database)
        try await transcripts.replaceLines(
            [StoreFixture.line("Vor der Pause.", at: 30)],
            for: try #require(first.id)
        )
        try await transcripts.replaceLines(
            [StoreFixture.line("Nach der Pause.", at: 20)],
            for: try #require(second.id)
        )
        _ = try await transcripts.annotate(at: 45, note: "wichtig", in: try #require(second.id))

        return (database, first, second)
    }

    // MARK: - What comes out

    /// The earliest recording survives, so its id — and every highlight,
    /// chapter and open window pointing at it — still means something.
    @Test("The first recording survives and carries the lesson's start time")
    func theFirstSurvives() async throws {
        let (database, first, second) = try await twoHalves()
        let library = LibraryRepository(database)

        let merged = try await library.merge(
            recordings: [try #require(second.id), try #require(first.id)]
        )

        #expect(merged.recording.id == first.id)
        #expect(merged.recording.startedAt == first.startedAt)
        #expect(try await library.recording(try #require(second.id)) == nil)
    }

    /// The lesson is as long as both halves. The gap between them is not
    /// recorded audio and there is nothing to lay in it.
    @Test("The merged recording runs as long as its parts together")
    func theDurationIsTheSum() async throws {
        let (database, first, second) = try await twoHalves()

        let merged = try await LibraryRepository(database).merge(
            recordings: [try #require(first.id), try #require(second.id)]
        )

        #expect(merged.recording.duration == 900)
    }

    /// The second half's transcript moves forward by the first half's length,
    /// so the lines read in the order they were said rather than interleaved.
    @Test("The transcript is laid end to end, in order")
    func theTranscriptIsLaidEndToEnd() async throws {
        let (database, first, second) = try await twoHalves()

        let merged = try await LibraryRepository(database).merge(
            recordings: [try #require(first.id), try #require(second.id)]
        )
        let lines = try await TranscriptRepository(database)
            .lines(for: try #require(merged.recording.id))

        #expect(lines.map(\.text) == ["Vor der Pause.", "Nach der Pause."])
        #expect(lines.map(\.start) == [30, 620])
    }

    /// What the user typed during the second half moves with it, or a mark made
    /// at minute twenty would land in the first half's minute twenty.
    @Test("Annotations move with their part")
    func annotationsMove() async throws {
        let (database, first, second) = try await twoHalves()

        let merged = try await LibraryRepository(database).merge(
            recordings: [try #require(first.id), try #require(second.id)]
        )
        let annotations = try await TranscriptRepository(database)
            .annotations(for: try #require(merged.recording.id))

        #expect(annotations.map(\.time) == [645])
    }

    /// The seams, so the transcript can say where the second sitting began.
    @Test("Each part records where it begins and when it was recorded")
    func theSeamsAreKept() async throws {
        let (database, first, second) = try await twoHalves()
        let library = LibraryRepository(database)

        let merged = try await library.merge(
            recordings: [try #require(first.id), try #require(second.id)]
        )
        let parts = try await library.parts(of: try #require(merged.recording.id))

        #expect(parts.map(\.offset) == [0, 600])
        #expect(parts.map(\.startedAt) == [first.startedAt, second.startedAt])
        #expect(parts.map(\.duration) == [600, 300])
    }

    /// Two sets of notes over two halves are not notes over the lesson, and the
    /// topic came from one of them. Both go, and the model is asked again.
    @Test("The notes and the topic are dropped, ready to be written again")
    func theNotesAreDropped() async throws {
        let (database, first, second) = try await twoHalves()
        let notes = NoteRepository(database)
        try await notes.replaceBlocks(
            [StoreFixture.noteBlock("## Erste Hälfte\nEin Absatz.")],
            for: try #require(first.id)
        )

        let merged = try await LibraryRepository(database).merge(
            recordings: [try #require(first.id), try #require(second.id)]
        )

        #expect(merged.recording.topic == nil)
        #expect(try await notes.blocks(for: try #require(merged.recording.id)).isEmpty)
    }

    // MARK: - What it refuses

    /// The microphone is open and the writer is appending to it; moving rows
    /// out from under that is not a merge, it is a corruption.
    @Test("A lecture that is still running is refused")
    func aRunningLectureIsRefused() async throws {
        let (database, first, second) = try await twoHalves()
        var running = second
        running.state = .recording
        try await LibraryRepository(database).save(running)

        await #expect(throws: RetainDatabaseError.cannotMergeWhileRecording) {
            try await LibraryRepository(database).merge(
                recordings: [try #require(first.id), try #require(running.id)]
            )
        }
    }

    @Test("One recording is nothing to merge")
    func oneIsNothingToMerge() async throws {
        let (database, first, _) = try await twoHalves()

        await #expect(throws: RetainDatabaseError.nothingToMerge) {
            try await LibraryRepository(database).merge(recordings: [try #require(first.id)])
        }
    }
}
