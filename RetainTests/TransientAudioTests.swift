import Foundation
import Testing

@testable import Retain

/// The audio is deleted once the transcript exists, and not one moment before.
///
/// Every test here writes a real file into a folder of its own and asks whether
/// it is still there afterwards. A fake file system would test the arrangement
/// of the code rather than the thing that matters, which is whether a lecture
/// can be lost.
@Suite("Transient audio")
struct TransientAudioTests {

    // MARK: - Fixtures

    /// A folder that exists for the length of one test, and a database to go
    /// with it.
    private func inAFolder(
        _ body: (URL, RetainDatabase) async throws -> Void
    ) async throws {
        let database = try StoreFixture.database()
        let directory = URL.temporaryDirectory
            .appendingPathComponent("retain-transient-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try await body(directory, database)
    }

    /// A recording with audio on disk, in the state a finished lecture is in.
    @discardableResult
    private func lecture(
        in database: RetainDatabase,
        course: Course,
        term: Term,
        directory: URL,
        filename: String,
        state: RecordingState = .done,
        transcript: [TranscriptLine] = []
    ) async throws -> Recording {
        guard let courseID = course.id, let termID = term.id else { throw StoreFixtureError.unsavedRow }

        var recording = try await LibraryRepository(database)
            .startRecording(in: courseID, during: termID, filename: filename)
        recording.state = state
        recording = try await LibraryRepository(database).save(recording)

        guard let id = recording.id else { throw StoreFixtureError.unsavedRow }
        try await TranscriptRepository(database).replaceLines(transcript, for: id)

        try Data("caf".utf8).write(to: directory.appendingPathComponent(filename))
        return recording
    }

    /// What the batch pass writes: the transcript of record.
    private var finalTranscript: [TranscriptLine] {
        [StoreFixture.line("Der Working Set ist die Menge der Seiten.", at: 0)]
    }

    /// What the live pass writes while the lecture runs. It is feedback, not
    /// the record, and it is in the database from the first minute.
    private var provisionalTranscript: [TranscriptLine] {
        [StoreFixture.line("der working set is die menge", at: 0, isProvisional: true)]
    }

    private func exists(_ filename: String, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path)
    }

    // MARK: - After a pass that worked

    @Test("A pass that stored a transcript leaves no audio behind")
    func transcribedAudioIsDeleted() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            let recording = try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "lecture.caf",
                transcript: finalTranscript
            )
            let id = try #require(recording.id)

            let discarded = await TransientAudio(database, directory: directory).discardAudio(of: id)

            #expect(discarded)
            #expect(exists("lecture.caf", in: directory) == false)
        }
    }

    @Test("The recording forgets the name of a file that is not there any more")
    func filenameIsCleared() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            let recording = try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "lecture.caf",
                transcript: finalTranscript
            )
            let id = try #require(recording.id)

            await TransientAudio(database, directory: directory).discardAudio(of: id)

            let stored = try await LibraryRepository(database).recording(id)
            #expect(stored?.filename == nil)
            // Everything the user keeps is untouched: only the audio went.
            #expect(stored?.state == .done)
            let lines = try await TranscriptRepository(database).lines(for: id)
            #expect(lines.count == 1)
        }
    }

    /// The next lecture is written into this folder. Deleting it would mean
    /// recreating it on the way into a recording, which is the worst moment to
    /// discover that it cannot be created.
    @Test("The folder survives the file")
    func theDirectoryStays() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            let recording = try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "lecture.caf",
                transcript: finalTranscript
            )

            let id = try #require(recording.id)
            await TransientAudio(database, directory: directory).discardAudio(of: id)

            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
    }

    // MARK: - After a pass that did not

    /// The live lines are in the database from the first minute of the lecture,
    /// so "there are transcript rows" is not the same question as "the batch
    /// pass landed". Getting this wrong means losing a lecture because a model
    /// crashed.
    @Test("A pass that failed keeps its audio, however many live lines were written")
    func failedPassKeepsItsAudio() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            let recording = try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "lecture.caf",
                transcript: provisionalTranscript
            )
            let id = try #require(recording.id)

            let discarded = await TransientAudio(database, directory: directory).discardAudio(of: id)

            #expect(discarded == false)
            #expect(exists("lecture.caf", in: directory))
            let stored = try await LibraryRepository(database).recording(id)
            #expect(stored?.filename == "lecture.caf")
        }
    }

    @Test("A recording with no transcript at all keeps its audio")
    func noTranscriptKeepsItsAudio() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            let recording = try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "lecture.caf"
            )

            let id = try #require(recording.id)
            let discarded = await TransientAudio(database, directory: directory).discardAudio(of: id)

            #expect(discarded == false)
            #expect(exists("lecture.caf", in: directory))
        }
    }

    @Test("A lecture that is still running is never touched")
    func aRunningLectureIsLeftAlone() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            let recording = try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "lecture.caf",
                state: .recording,
                transcript: finalTranscript
            )

            let id = try #require(recording.id)
            let discarded = await TransientAudio(database, directory: directory).discardAudio(of: id)

            #expect(discarded == false)
            #expect(exists("lecture.caf", in: directory))
        }
    }

    // MARK: - The launch sweep

    @Test("The sweep deletes the file whose transcript exists and leaves the one whose does not")
    func sweepPicksTheRightFiles() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "transcribed.caf",
                transcript: finalTranscript
            )
            try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "failed.caf",
                transcript: provisionalTranscript
            )

            let discarded = await TransientAudio(database, directory: directory).sweep()

            #expect(discarded == 1)
            #expect(exists("transcribed.caf", in: directory) == false)
            #expect(exists("failed.caf", in: directory))
        }
    }

    /// The crash this sweep exists for: the file was deleted and the process
    /// died before the row was written. The name still has to go, or the next
    /// launch walks the same row again for ever.
    @Test("A name left pointing at a file that is already gone is cleared")
    func sweepClearsADanglingName() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            let recording = try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "lecture.caf",
                transcript: finalTranscript
            )
            let id = try #require(recording.id)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("lecture.caf"))

            let discarded = await TransientAudio(database, directory: directory).sweep()
            let stored = try await LibraryRepository(database).recording(id)

            #expect(discarded == 1)
            #expect(stored?.filename == nil)
        }
    }

    @Test("A sweep with nothing to do changes nothing")
    func sweepOfATidyLibrary() async throws {
        try await inAFolder { directory, database in
            let library = try await StoreFixture.library(in: database)
            let recording = try await lecture(
                in: database,
                course: library.course,
                term: library.term,
                directory: directory,
                filename: "lecture.caf",
                transcript: finalTranscript
            )
            let id = try #require(recording.id)
            let audio = TransientAudio(database, directory: directory)

            let first = await audio.sweep()
            let second = await audio.sweep()
            let stored = try await LibraryRepository(database).recording(id)

            #expect(first == 1)
            #expect(second == 0)
            // The recording itself is untouched. It is the file that went.
            #expect(stored != nil)
        }
    }
    // MARK: - A lecture nobody spoke in

    /// A silent lecture produces no final transcript lines, which at the row
    /// level is indistinguishable from a pass that crashed — `.done` is written
    /// by both paths. So the row cannot answer it and the pass itself has to
    /// say so. Without that, the silent one keeps its file for ever and is
    /// re-examined at every launch.
    @Test("A finished pass that produced nothing still releases the audio")
    func silentLectureIsCleanedUp() async throws {
        try await inAFolder { directory, database in
            let term = try await StoreFixture.term(in: database)
            let course = try await StoreFixture.course(in: database, term: term)
            let recording = try await lecture(
                in: database,
                course: course,
                term: term,
                directory: directory,
                filename: "silent.caf",
                transcript: []
            )
            guard let id = recording.id else { return }

            let discarded = await TransientAudio(database, directory: directory)
                .discardAudio(of: id, passFinished: true)

            #expect(discarded)
            #expect(!exists("silent.caf", in: directory))
        }
    }

    /// The half that must not be weakened with it, and the reason the sweep
    /// never says `passFinished`: from outside that moment the transcript is
    /// the only honest evidence, and losing a lecture because a model crashed
    /// is the one outcome here worth any amount of disk.
    @Test("The sweep still keeps a silent lecture, having no way to know")
    func theSweepCannotTellAndKeepsIt() async throws {
        try await inAFolder { directory, database in
            let term = try await StoreFixture.term(in: database)
            let course = try await StoreFixture.course(in: database, term: term)
            try await lecture(
                in: database,
                course: course,
                term: term,
                directory: directory,
                filename: "silent.caf",
                transcript: []
            )

            await TransientAudio(database, directory: directory).sweep()

            #expect(exists("silent.caf", in: directory))
        }
    }
}
