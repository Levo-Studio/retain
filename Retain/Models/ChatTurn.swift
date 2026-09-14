import Foundation

/// Where a chat answer came from.
///
/// Board 04 draws these as small chips under the model's answer: `00:38:20` and
/// `Notiz 1`. They are the difference between an answer a student can check and
/// one they have to believe, which matters more here than usual — the model is
/// small, it is answering from a transcript with recognition errors in it, and
/// it is talking to somebody who was not paying full attention at the time.
nonisolated enum ChatReference: Hashable, Sendable, Codable {

    /// A second in the recording. The chip brings the transcript forward at
    /// the line that was said then.
    case transcript(TimeInterval)

    /// A note block, by its number.
    case note(Int)
}

/// One turn of the chat rail.
nonisolated struct ChatTurn: Identifiable, Hashable, Sendable, Codable {

    enum Author: String, Hashable, Sendable, Codable {
        /// Drawn as the bubble on the right, "Von dir".
        case you
        case model
    }

    let id: UUID
    var author: Author
    var text: String

    /// Empty for a question, and empty for an answer the model could not source
    /// — which is worth drawing as nothing rather than as a guessed chip.
    var references: [ChatReference]

    /// When the turn was made. Wall clock, not a position in the recording:
    /// the chat happens afterwards.
    var date: Date

    init(
        id: UUID = UUID(),
        author: Author,
        text: String,
        references: [ChatReference] = [],
        date: Date = Date()
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.references = references
        self.date = date
    }
}

// MARK: - When the chat can be used

/// Whether this recording can be asked questions yet.
///
/// A state rather than an error, because the interface has to draw the reason:
/// the chat rail is on screen while the recording is still running, and "not
/// yet, the summary is still being written" is something to say in the rail
/// rather than something to discover by sending a question into a failure.
nonisolated enum ChatAvailability: Hashable, Sendable {

    /// The recording has not stopped. The model would be answering from half a
    /// transcript and no notes.
    case stillRecording

    /// Stopped, but the notes are not written yet.
    case summaryPending

    case ready

    /// - Parameters:
    ///   - isRecording: whether the recording is still running or paused.
    ///   - hasNotes: whether the reduce has finished.
    static func of(isRecording: Bool, hasNotes: Bool) -> ChatAvailability {
        if isRecording { return .stillRecording }
        return hasNotes ? .ready : .summaryPending
    }
}
