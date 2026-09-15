import Foundation

/// When a line of the live transcript opens, continues and closes.
///
/// Pulled out of `LiveTranscriber` and made a pure value so it can be tested
/// against a written-down sequence of coughs and pauses, rather than only
/// against a room. It holds no audio and no model: it is told how many samples
/// arrived and what the voice-activity model made of them, and answers with
/// what to do with them.
///
/// **The gate does not decide whether the speech model hears the lecture.** It
/// decides where a line ends. Those were the same decision once, and then a
/// cough closed the gate and the next twenty seconds of the lesson were dropped
/// on the way to the model — which is unrecoverable, because the live
/// transcript has no second pass over the audio.
nonisolated struct LiveGate {

    /// What the voice-activity model said about a chunk.
    enum Signal: Equatable, Sendable {

        /// It has just decided this is speech.
        case start

        /// It has just decided the speech is over. An opinion, not an
        /// instruction — see `hangoverSamples`.
        case end

        /// Nothing changed.
        case quiet
    }

    /// What to do with the chunk that was just described.
    enum Step: Equatable, Sendable {

        /// Do not feed it. Keep it as pre-roll for the next line to begin from.
        case keep

        /// A line starts here: feed the pre-roll that was kept, then the chunk.
        case open(lineStart: Int)

        /// Feed it into the open line.
        case feed

        /// Feed it, then close the line at this sample and stop feeding.
        case close(at: Int)

        /// Feed it, close the line at this sample and immediately start
        /// another. The voice has not stopped; the line has only got too long.
        case cut(at: Int)
    }

    /// How long audio keeps flowing after the model says the speech stopped.
    let hangoverSamples: Int

    /// How much audio from before a line opens is kept to start it with.
    let preRollSamples: Int

    /// The longest a line may run before it is cut and the decoder reset.
    let longestLineSamples: Int

    /// Samples seen, which is the recording's own timeline.
    private(set) var processed = 0

    /// Where the open line began.
    private(set) var lineStart = 0

    /// Whether a line is open and audio is reaching the model.
    private(set) var isOpen = false

    /// What the voice-activity model last said, which is not the same as
    /// whether a line is open.
    private var speaking = false

    /// Samples fed since the model said the speech stopped.
    private var hangover = 0

    /// How much pre-roll is in hand, capped at `preRollSamples`.
    private var kept = 0

    init(hangoverSamples: Int, preRollSamples: Int, longestLineSamples: Int) {
        self.hangoverSamples = hangoverSamples
        self.preRollSamples = preRollSamples
        self.longestLineSamples = longestLineSamples
    }

    /// Takes one chunk's worth of signal and says what to do with it.
    mutating func advance(_ signal: Signal, chunk: Int) -> Step {
        let chunkStart = processed
        processed += chunk

        switch signal {
        case .start:
            speaking = true
            hangover = 0
            guard !isOpen else { return .feed }

            // The chunk that crosses the threshold is the one holding the first
            // syllable, so the syllable before it is in a chunk already gone.
            // The line is dated back over the pre-roll that is about to be fed
            // with it.
            isOpen = true
            lineStart = max(0, chunkStart - kept)
            kept = 0
            return .open(lineStart: lineStart)

        case .end:
            speaking = false
            hangover = 0
            guard isOpen else { return remember(chunk) }
            return .feed

        case .quiet:
            guard isOpen else { return remember(chunk) }

            if !speaking {
                hangover += chunk
                guard hangover >= hangoverSamples else { return .feed }

                // Dated where the model said the silence began, so the line is
                // not three seconds of nothing longer than what was said in it.
                let end = processed - hangover
                isOpen = false
                hangover = 0
                kept = 0
                return .close(at: end)
            }

            guard processed - lineStart >= longestLineSamples else { return .feed }

            // A line that never ends is a decoder state that never resets, and
            // a streaming RNN-T that has not been reset in ten minutes is
            // transcribing its own history rather than the room. The cut hands
            // straight over to a new line: the model is still triggered, so it
            // will send no second `start` to reopen the gate, and stopping here
            // would stop the transcript for the rest of the lecture.
            lineStart = processed
            return .cut(at: processed)
        }
    }

    private mutating func remember(_ chunk: Int) -> Step {
        kept = min(kept + chunk, preRollSamples)
        return .keep
    }
}
