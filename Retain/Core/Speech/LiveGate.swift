import Foundation

/// Where a line of the live transcript begins and ends.
///
/// Pulled out of `LiveTranscriber` and made a pure value so it can be tested
/// against a written-down lesson — a cough, a pause, a voice from the back of
/// the room — rather than only against a room. It holds no audio and no model:
/// it is told how many samples arrived and what the voice-activity model made
/// of them, and answers with what to do with them.
///
/// **Every chunk is fed to the speech model. The voice-activity model does not
/// decide what is heard, only where the lines break.** It decided both once,
/// and it was wrong in both directions: a cough closed a line and the twenty
/// seconds after it were dropped on the way to the model, and a lecturer across
/// the room never cleared the bar at all, so a voice that is plainly audible on
/// the recording never reached the live transcript. Lowering the bar did not
/// fix the second one, because a distant voice is genuinely a faint signal. The
/// gate was therefore taken off the audio path entirely.
///
/// What is left for it to do is real: it puts the line breaks where the speech
/// actually stops, which is what makes the transcript readable. When it says
/// nothing at all the transcript still arrives — in lines cut at
/// `longestLineSamples` instead of at sentences.
nonisolated struct LiveGate {

    /// What the voice-activity model said about a chunk.
    enum Signal: Equatable, Sendable {

        /// It has just decided this is speech.
        case start

        /// It has just decided the speech is over. An opinion, and one it holds
        /// for a tenth of a second after a cough — see `hangoverSamples`.
        case end

        /// Nothing changed.
        case quiet
    }

    /// What to do with the chunk that was just described. Every case feeds it.
    enum Step: Equatable, Sendable {

        /// Feed it. No line has begun yet, and when one does it begins here.
        case idle(lineStart: Int)

        /// Feed it. A line begins here.
        case open(lineStart: Int)

        /// Feed it into the line that is open.
        case feed

        /// Feed it, then close the line at this sample and reset the decoder.
        case close(at: Int)
    }

    /// How long a line stays open after the model says the speech stopped.
    ///
    /// A cough, a door or a bang makes the microphone's automatic gain duck,
    /// and the speech that follows sits under any threshold for several seconds
    /// until the gain comes back. Waiting this long before believing it means a
    /// voice that comes back continues the same line.
    let hangoverSamples: Int

    /// The longest anything may run before the line is closed and the decoder
    /// reset, whether a line was ever opened or not.
    ///
    /// Both halves matter. An open line that never closes is a decoder state
    /// that never resets, and a streaming RNN-T that has not been reset in ten
    /// minutes is transcribing its own history rather than the room. And audio
    /// that the model never flagged as speech is closed on this timer too —
    /// which is what puts a distant voice into the transcript even when nothing
    /// ever said it was speaking. What decoded to nothing is dropped, so the
    /// timer costs nothing during real silence.
    let longestLineSamples: Int

    /// How far behind the present a line's start is allowed to sit while
    /// nothing has begun.
    ///
    /// Without it a line preceded by nineteen seconds of quiet would be dated
    /// nineteen seconds early. With it both mistakes — a line dated early, and
    /// one dated late because the speech in it was never flagged — stay inside
    /// this much. These timestamps are provisional and the batch pass replaces
    /// them wholesale; what matters is that the live transcript does not read
    /// as if the lecturer spoke half a minute before they did.
    let idleLagSamples: Int

    /// Samples seen, which is the recording's own timeline.
    private(set) var processed = 0

    /// Where the line that is open — or the one that would open next — begins.
    private(set) var lineStart = 0

    /// Whether the voice-activity model has declared speech for the line in
    /// hand. Not whether audio is flowing; audio always is.
    private(set) var isOpen = false

    private var speaking = false
    private var hangover = 0

    /// Samples since the decoder was last reset, which is not the same as
    /// samples since the line opened — the line can open long after the reset.
    private var sinceReset = 0

    init(hangoverSamples: Int, longestLineSamples: Int, idleLagSamples: Int) {
        self.hangoverSamples = hangoverSamples
        self.longestLineSamples = longestLineSamples
        self.idleLagSamples = idleLagSamples
    }

    /// Takes one chunk's worth of signal and says what to do with it.
    mutating func advance(_ signal: Signal, chunk: Int) -> Step {
        processed += chunk
        sinceReset += chunk

        switch signal {
        case .start:
            speaking = true
            hangover = 0
        case .end:
            speaking = false
            hangover = 0
        case .quiet:
            if isOpen && !speaking { hangover += chunk }
        }

        if isOpen {
            // Dated where the model said the silence began, so the line is not
            // three seconds of nothing longer than what was said in it.
            if !speaking && hangover >= hangoverSamples { return close(at: processed - hangover) }
            if sinceReset >= longestLineSamples { return close(at: processed) }
            return .feed
        }

        // A line closed on the timer while the speech ran straight through it
        // hands straight over to the next one. Stopping here would stop the
        // transcript for the rest of the lecture.
        if speaking {
            isOpen = true
            return .open(lineStart: lineStart)
        }

        if sinceReset >= longestLineSamples { return close(at: processed) }

        lineStart = max(lineStart, processed - idleLagSamples)
        return .idle(lineStart: lineStart)
    }

    private mutating func close(at end: Int) -> Step {
        isOpen = false
        hangover = 0
        sinceReset = 0
        lineStart = end
        return .close(at: end)
    }
}
