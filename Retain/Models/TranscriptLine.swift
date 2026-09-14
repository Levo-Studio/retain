import Foundation

/// Who said something.
///
/// The design draws two: the person teaching and a question from the room.
/// Diarization does not know which is which — it produces anonymous clusters —
/// so the mapping from cluster to role is a separate decision, made in
/// `SpeakerRoles`.
nonisolated enum SpeakerRole: Hashable, Sendable, Codable {

    /// The person teaching. Amber rule and "Speaker" in the transcript rail.
    case lecturer

    /// A question or a comment from the room.
    case audience

    /// Before diarization has run, which is every line of the live transcript.
    /// The live pass is feedback, not the record, and it does not separate
    /// speakers.
    case unknown
}

/// One line of transcript.
///
/// The same type carries the live pass and the batch pass, because everything
/// downstream — the UI, the store, the summariser — treats them the same way
/// apart from `isProvisional`.
nonisolated struct TranscriptLine: Identifiable, Hashable, Sendable, Codable {

    let id: UUID

    /// Seconds from the start of the recording. Not a wall-clock time: the
    /// recording is the timeline, and it is what a click in the transcript
    /// seeks to.
    var start: TimeInterval
    var end: TimeInterval

    var text: String
    var speaker: SpeakerRole

    /// True while this line came from the streaming pass.
    ///
    /// Streaming sits around 10 % word error on German and batch around 5.9 %,
    /// so a provisional line is shown and then replaced rather than kept. The
    /// notes are always built from the lines where this is false.
    var isProvisional: Bool

    var duration: TimeInterval { end - start }

    init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        speaker: SpeakerRole = .unknown,
        isProvisional: Bool = false
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.isProvisional = isProvisional
    }
}

/// A stretch of audio one cluster was speaking over, as diarization reports it.
///
/// Retain's own type rather than FluidAudio's, so the pipeline can be tested
/// without the framework and without a model.
nonisolated struct SpeakerSegment: Hashable, Sendable {
    let speakerID: String
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { end - start }
}

/// One word with the time it was said, as the batch pass reports it.
///
/// This is what makes clicking a line in the transcript seek to the right
/// second, and what lets a speaker segment be matched to the words inside it.
nonisolated struct WordTiming: Hashable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}
