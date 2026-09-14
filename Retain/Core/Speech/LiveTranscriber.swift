import FluidAudio
import Foundation

/// The transcript that runs along beside the lecture.
///
/// Audio arrives in blocks of 16 kHz mono float from the recording writer. Each
/// block goes through voice activity detection first, and only speech reaches
/// the streaming model — which is the difference between decoding ninety
/// minutes and decoding the sixty a lecturer actually talks for, on a battery
/// that has to last the day.
///
/// **What comes out of here is feedback, not the record.** The streaming model
/// sits around 10 % word error on German against the batch model's 5.9 %, so
/// these lines are shown while the lecture runs and replaced wholesale
/// afterwards. Nothing downstream builds notes from them.
///
/// An actor because the audio callback's queue, the UI and the model all reach
/// it, and because FluidAudio's own managers are actors.
actor LiveTranscriber {

    /// A finished line, or the one still forming.
    enum Update: Sendable {
        /// The model's current guess at what is being said right now. Replaced
        /// by the next one, and by `line` when the utterance ends.
        case partial(String)

        /// An utterance ended and the model settled on this.
        case line(TranscriptLine)
    }

    private let streaming: StreamingNemotronMultilingualAsrManager
    private let vad: VadManager
    private let onUpdate: @Sendable (Update) -> Void

    /// Samples the VAD has not been given yet, because they did not fill a
    /// chunk. The VAD model takes fixed-size windows.
    private var pending: [Float] = []

    private var vadState: VadStreamState
    private var speaking = false

    /// Where the current utterance began, in samples from the start of the
    /// recording. Times come from the sample count rather than from a clock:
    /// the recording is the timeline, and a wall clock would drift from it.
    private var utteranceStartSample = 0
    private var processedSamples = 0

    init(models: SpeechModels.Prepared, onUpdate: @escaping @Sendable (Update) -> Void) async {
        self.streaming = StreamingNemotronMultilingualAsrManager()
        self.vad = models.vad
        self.onUpdate = onUpdate
        self.vadState = await models.vad.makeStreamState()

        try? await streaming.loadFromShared(models.streaming)
        await streaming.setLanguage(SpeechModels.languageCode)
        await streaming.setPartialCallback { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onUpdate(.partial(trimmed))
        }
    }

    // MARK: - Feeding

    /// Hands one block of recorded audio in. Called from the writer queue,
    /// never from the audio callback.
    func append(_ samples: [Float]) async {
        pending.append(contentsOf: samples)

        while pending.count >= VadManager.chunkSize {
            let chunk = Array(pending.prefix(VadManager.chunkSize))
            pending.removeFirst(VadManager.chunkSize)
            await consume(chunk)
        }
    }

    private func consume(_ chunk: [Float]) async {
        let chunkStart = processedSamples
        processedSamples += chunk.count

        guard let result = try? await vad.processStreamingChunk(chunk, state: vadState) else {
            // A VAD failure must not silence the lecture. Falling through to
            // the ASR costs power and decodes some silence; dropping the audio
            // would lose words, and only one of those is recoverable.
            //
            // The discarded result is not an oversight: process(samples:)
            // always returns the empty string. Partial text arrives through
            // setPartialCallback and the settled text through finish(). The
            // framework's own documentation says otherwise in places; the
            // source is what this follows.
            _ = try? await streaming.process(samples: chunk)
            return
        }
        vadState = result.state

        switch result.event?.kind {
        case .speechStart:
            speaking = true
            utteranceStartSample = chunkStart
            _ = try? await streaming.process(samples: chunk)

        case .speechEnd:
            _ = try? await streaming.process(samples: chunk)
            await endUtterance(at: processedSamples)

        case .none:
            guard speaking else { return }
            _ = try? await streaming.process(samples: chunk)

        @unknown default:
            guard speaking else { return }
            _ = try? await streaming.process(samples: chunk)
        }
    }

    /// Closes the utterance, emits it, and puts the model back to a clean
    /// state.
    ///
    /// The reset is not optional. A streaming RNN-T carries its decoder state
    /// forward, so without it the next utterance is decoded as a continuation
    /// of the last one and the transcript drifts further from the audio the
    /// longer the lecture runs.
    private func endUtterance(at endSample: Int) async {
        speaking = false

        guard let text = try? await streaming.finish() else {
            await streaming.reset()
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await streaming.reset()
        guard !trimmed.isEmpty else { return }

        let rate = CaptureFormat.sampleRate
        onUpdate(
            .line(
                TranscriptLine(
                    start: Double(utteranceStartSample) / rate,
                    end: Double(endSample) / rate,
                    text: trimmed,
                    speaker: .unknown,
                    isProvisional: true
                )
            )
        )
    }

    /// Flushes whatever is still in hand. Called when the recording stops, so
    /// the last sentence of the lecture is not the one that goes missing.
    func finish() async {
        if !pending.isEmpty {
            let remainder = pending
            pending = []
            processedSamples += remainder.count
            _ = try? await streaming.process(samples: remainder)
        }
        if speaking {
            await endUtterance(at: processedSamples)
        }
        await streaming.cleanup()
    }
}
