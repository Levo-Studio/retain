import Foundation

/// What deleting one recording costs, counted before anyone agrees to it.
///
/// A recording is a lecture somebody sat through once and cannot sit through
/// again, and by the time it is in the library the audio is usually already
/// gone — deleted as soon as it was transcribed, which is the whole design.
/// What is left is the only copy of what was said. So the confirmation does not
/// ask "are you sure"; it says what goes, counted.
nonisolated struct RecordingDeletion: Equatable, Sendable {

    /// Lines of transcript. Zero for a recording whose batch pass never ran.
    let transcriptLines: Int

    /// Note blocks the model wrote.
    let noteBlocks: Int

    /// `⌘⇧M` marks the user typed during the lecture. The one thing here nobody
    /// else could produce again.
    let annotations: Int

    /// Passages of the notes the user marked.
    let highlights: Int

    /// True while the audio file is still on disk, which is the short window
    /// between the lecture ending and the batch pass finishing.
    let hasAudio: Bool

    /// True while this is the lecture being recorded right now. Deleting it is
    /// refused rather than confirmed: the microphone is open and the writer is
    /// holding the file.
    let isRecording: Bool

    /// Nothing written yet — a recording that was started and produced nothing,
    /// which is what a crash leaves behind.
    var isEmpty: Bool {
        transcriptLines == 0 && noteBlocks == 0 && annotations == 0 && highlights == 0
    }
}
