import Foundation

/// The audio is working material, not an archive.
///
/// A recording exists in order to be transcribed. It is written during the
/// lecture, read twice after it — once by the batch pass and once by
/// diarization — and then it is gone. What the user keeps is the transcript,
/// the notes, the annotations and the highlights, because that is what they
/// read. Ninety minutes of 16 kHz mono Int16 is about 173 MB, and a school year
/// of it is tens of gigabytes of files nobody can open and nobody will play.
///
/// Two rules hold everywhere in here, and they are the whole design:
///
/// 1. **Audio whose transcript was not stored is never deleted.** "Stored"
///    means a line the batch pass wrote — `isProvisional == false`. The live
///    lines are feedback at around 10 % word error and they are written during
///    the lecture, so a recording whose batch pass crashed still has rows in the
///    transcript table; deleting on the strength of those would lose the lecture
///    because a model fell over, which is the one outcome worth any amount of
///    disk.
/// 2. **The file goes, the folder stays.** `RecordingStore.directory` is where
///    the next lecture is written, and removing it would mean the next
///    `start` has to create it again.
///
/// Nothing here runs on the audio thread — it runs after the lecture and at
/// launch — so the real-time rules that govern the rest of `Core/Audio/` do not
/// reach it.
nonisolated struct TransientAudio: Sendable {

    private let library: LibraryRepository
    private let transcript: TranscriptRepository

    /// Taken rather than read from `RecordingStore` at every call so a test can
    /// point the whole type at a folder of its own. There is exactly one folder
    /// in the app.
    private let directory: URL

    init(_ database: RetainDatabase, directory: URL = RecordingStore.directory) {
        library = LibraryRepository(database)
        transcript = TranscriptRepository(database)
        self.directory = directory
    }

    // MARK: - One recording

    /// Deletes one recording's audio, now that everything that had to read it
    /// has.
    ///
    /// Called once, at the end of the pass after the lecture: after the batch
    /// transcription *and* the diarization, and after the transcript has been
    /// written. Not when the recording stops — diarization still has to read the
    /// file — and not after the summary, because a summary that failed must not
    /// cost the audio before it can be retried.
    ///
    /// - Returns: whether the recording has no audio any more, which includes
    ///   the case where the file was already gone.
    @discardableResult
    /// - Parameter passFinished: set only by the transcription pass's own
    ///   success branch, where the caller knows something the row cannot say.
    ///   A lecture nobody spoke in produces no final lines, and at the row
    ///   level that is indistinguishable from a pass that crashed — so without
    ///   this the silent one would keep its file for ever and be re-examined at
    ///   every launch. The sweep never passes it: from outside that moment, the
    ///   transcript is the only honest evidence.
    func discardAudio(of recordingID: Int64, passFinished: Bool = false) async -> Bool {
        guard let recording = try? await library.recording(recordingID) else { return false }
        return await discard(recording, passFinished: passFinished)
    }

    // MARK: - The launch sweep

    /// Finishes the deletions a quit or a crash interrupted.
    ///
    /// Between writing the transcript and deleting the file there is a moment
    /// where both exist, and a process that dies in it leaves the file behind
    /// for ever. This is the only place that is looked for. There is no timer
    /// and no periodic scan: Retain is supposed to last a school day on a
    /// battery, and a sweep that finds nothing is the normal outcome — which
    /// makes every repeat of it pure cost.
    ///
    /// - Returns: how many recordings lost their audio.
    @discardableResult
    func sweep() async -> Int {
        // One query, not a walk of the whole library. The filename is cleared
        // when the audio goes, so the rows that still name a file are exactly
        // the rows worth looking at — on a settled install, none of them.
        guard let candidates = try? await library.recordingsWithAudio() else { return 0 }

        var discarded = 0
        for recording in candidates where await discard(recording) {
            discarded += 1
        }
        return discarded
    }

    // MARK: -

    /// The one place a recording loses its audio.
    ///
    /// The order is: delete the file, and only then forget its name. A name
    /// cleared before a deletion that then failed would be a file nothing can
    /// find again — the sweep walks the database, not the folder.
    private func discard(_ recording: Recording, passFinished: Bool = false) async -> Bool {
        guard let recordingID = recording.id else { return false }
        guard let filename = recording.filename, !filename.isEmpty else { return false }

        // A row still marked as running is a lecture in progress, or one a
        // crash left looking like it. Either way the file may have a writer on
        // it, and neither is a recording that has been transcribed.
        guard recording.state != .recording else { return false }

        // The transcript, not the state. `.done` is written by the failure path
        // too — a pass that crashed closes the row rather than leaving it
        // saying it is still recording for ever — so a state check here would
        // delete exactly the audio that has to survive for a retry.
        if !passFinished {
            guard await hasFinalTranscript(recordingID) else { return false }
        }

        let url = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) {
            // A file that cannot be removed keeps its name in the database, so
            // the next launch tries again rather than orphaning it.
            guard (try? FileManager.default.removeItem(at: url)) != nil else { return false }
        }

        var cleared = recording
        cleared.filename = nil
        _ = try? await library.save(cleared)
        return true
    }

    /// Whether the transcript of record is in the database.
    ///
    /// Read as the whole transcript rather than as a count, because there is no
    /// counting query outside `Core/Data/` and this runs for at most a handful
    /// of recordings: the sweep only asks about rows that still name a file,
    /// and after the first successful pass there are none.
    private func hasFinalTranscript(_ recordingID: Int64) async -> Bool {
        guard let lines = try? await transcript.lines(for: recordingID) else { return false }
        return lines.contains { !$0.isProvisional }
    }
}
