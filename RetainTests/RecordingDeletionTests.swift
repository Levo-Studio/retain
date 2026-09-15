import Foundation
import GRDB
import Testing

@testable import Retain

/// Deleting one recording — the second place in Retain where work is destroyed,
/// and the sharper of the two.
///
/// A term at least announces itself as a big thing. A recording is one row in a
/// table, and by the time it is in that table its audio is already gone: it is
/// deleted as soon as the batch pass finishes, which is the whole design. The
/// transcript **is** the lecture. There is nothing to run the pass over again.
@Suite("Deleting a recording")
struct RecordingDeletionTests {

    private func lecture(
        in database: RetainDatabase,
        filename: String? = nil,
        state: RecordingState = .done
    ) async throws -> Recording {
        let term = try await StoreFixture.term(in: database, title: "Third year, winter", isCurrent: true)
        let course = try await StoreFixture.course(in: database, term: term, name: "Informatik")
        var recording = try await StoreFixture.recording(
            in: database,
            course: course,
            term: term,
            at: StoreFixture.instant(2025, 11, 3, 10, 0)
        )
        recording.state = state
        recording.filename = filename
        return try await LibraryRepository(database).save(recording)
    }

    private func write(lines: Int, to recordingID: Int64, in database: RetainDatabase) async throws {
        let transcript = TranscriptRepository(database)
        for index in 0..<lines {
            try await transcript.append(
                StoreFixture.line("Zeile \(index)", at: Double(index) * 5),
                to: recordingID
            )
        }
    }

    // MARK: - What the confirmation is told

    @Test("The count names the transcript, the notes and the annotations")
    func theImpactCountsWhatWasWritten() async throws {
        let database = try StoreFixture.database()
        let recording = try await lecture(in: database)
        let id = try #require(recording.id)
        try await write(lines: 3, to: id, in: database)

        let impact = try await LibraryRepository(database).deletionImpact(ofRecording: id)

        #expect(impact.transcriptLines == 3)
        #expect(impact.isEmpty == false)
        // The audio was already released when the pass finished, which is the
        // ordinary state and the reason this deletion is final.
        #expect(impact.hasAudio == false)
        #expect(impact.isRecording == false)
    }

    @Test("A recording that holds nothing reports nothing lost")
    func theImpactOfAnEmptyRecording() async throws {
        let database = try StoreFixture.database()
        let recording = try await lecture(in: database)

        let impact = try await LibraryRepository(database).deletionImpact(
            ofRecording: try #require(recording.id)
        )

        #expect(impact.isEmpty)
    }

    @Test("Audio still on disk is reported, because then it goes too")
    func theImpactNoticesAudio() async throws {
        let database = try StoreFixture.database()
        let recording = try await lecture(in: database, filename: "2025-11-03-100000-abc123.caf")

        let impact = try await LibraryRepository(database).deletionImpact(
            ofRecording: try #require(recording.id)
        )

        #expect(impact.hasAudio)
    }

    // MARK: - What the deletion does

    @Test("The recording and its transcript go")
    func deletingTakesTheTranscript() async throws {
        let database = try StoreFixture.database()
        let recording = try await lecture(in: database)
        let id = try #require(recording.id)
        try await write(lines: 4, to: id, in: database)

        try await LibraryRepository(database).delete(recording: id)

        let counts = try await database.writer.read { db in
            (
                recordings: try Recording.fetchCount(db),
                lines: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcriptLine") ?? -1
            )
        }
        #expect(counts.recordings == 0)
        #expect(counts.lines == 0)
    }

    @Test("Deleting hands back the audio's name so the file can go with it")
    func deletingReportsTheAudio() async throws {
        let database = try StoreFixture.database()
        let recording = try await lecture(in: database, filename: "2025-11-03-100000-abc123.caf")

        let filename = try await LibraryRepository(database).delete(
            recording: try #require(recording.id)
        )

        // The repository does not touch the disk — `TransientAudio` and the
        // dialog's own action do — so the name is returned rather than acted
        // on. A file left behind would be a recording nothing can ever read.
        #expect(filename == "2025-11-03-100000-abc123.caf")
    }

    @Test("A recording that is running is refused")
    func aRunningRecordingIsRefused() async throws {
        let database = try StoreFixture.database()
        let recording = try await lecture(
            in: database,
            filename: "2025-11-03-100000-abc123.caf",
            state: .recording
        )
        let id = try #require(recording.id)

        let filename = try await LibraryRepository(database).delete(recording: id)

        // The microphone is open and the writer is holding that file. Deleting
        // the row underneath it would leave a recording writing into a lecture
        // that no longer exists.
        #expect(filename == nil)
        #expect(try await database.writer.read { try Recording.fetchCount($0) } == 1)
    }

    @Test("The confirmation says a running recording has to be stopped first")
    func theBodySaysToStopFirst() {
        let sentences = DeleteRecordingDialog.sentences(
            name: "Informatik · Today · 10:00",
            impact: RecordingDeletion(
                transcriptLines: 12, noteBlocks: 2, annotations: 1,
                highlights: 0, hasAudio: true, isRecording: true
            )
        )
        #expect(sentences.contains("Stop it first"))
        #expect(!sentences.contains("cannot be undone"))
    }

    @Test("The confirmation says the audio is already gone when it is")
    func theBodySaysTheAudioIsGone() {
        let sentences = DeleteRecordingDialog.sentences(
            name: "Informatik · Today · 10:00",
            impact: RecordingDeletion(
                transcriptLines: 12, noteBlocks: 2, annotations: 1,
                highlights: 0, hasAudio: false, isRecording: false
            )
        )
        // The sentence that makes this different from every other deletion.
        #expect(sentences.contains("only copy"))
        #expect(sentences.contains("cannot be undone"))
        #expect(sentences.contains("12"))
    }

    // MARK: - After a crash

    @Test("A recording left mid-flight is settled at launch")
    func aCrashedRecordingIsSettled() async throws {
        let database = try StoreFixture.database()
        let recording = try await lecture(in: database, state: .recording)
        let repository = LibraryRepository(database)

        let settled = try await repository.settleInterruptedRecordings()

        #expect(settled == 1)
        let again = try await repository.recording(try #require(recording.id))
        // It used to be drawn as "recording" in red for ever: a claim that
        // something is happening to it, made by a process that no longer
        // exists, which the user could neither act on nor clear.
        #expect(again?.state == .done)
    }

    @Test("Settling leaves a finished recording alone")
    func settlingLeavesFinishedRecordings() async throws {
        let database = try StoreFixture.database()
        let recording = try await lecture(in: database, state: .done)
        let repository = LibraryRepository(database)

        #expect(try await repository.settleInterruptedRecordings() == 0)
        #expect(try await repository.recording(try #require(recording.id))?.state == .done)
    }
}
