import CoreML
import FluidAudio
import Foundation

/// Fetches and holds the speech models.
///
/// Three sets, downloaded once and used offline afterwards:
///
/// - the **streaming** model, Nemotron multilingual at the 1120 ms tier, which
///   produces the live transcript during the lecture;
/// - the **batch** model, Parakeet TDT v3, which re-transcribes the recording
///   afterwards and is what the notes are built from;
/// - the **voice-activity** model, which gates the streaming model so it is not
///   decoding silence for ninety minutes.
///
/// **Nothing here passes an `MLModelConfiguration`.** Every FluidAudio manager
/// defaults to `.cpuAndNeuralEngine`, and hard rule 4 exists because handing it
/// `.all` instead sends the int8 operations to the GPU, where they run roughly
/// ten times slower at several times the power. The absence of a configuration
/// argument below is the rule, not an oversight — see the comments at each call.
@MainActor
@Observable
final class SpeechModels {

    enum State: Equatable, Sendable {
        case notLoaded
        /// Fraction 0…1 where the source reports one.
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .notLoaded

    /// Kept so a second lecture does not re-download or re-compile anything.
    private(set) var streaming: SharedNemotronMultilingualModels?
    private(set) var batch: AsrModels?
    private(set) var vad: VadManager?

    /// The language the streaming model is asked for. German, per the locked
    /// decision; `languageDirectory(for:)` routes `de-DE` to the Latin-script
    /// vocabulary, which is the smaller and faster of the two ships.
    ///
    /// `nonisolated` because the batch passes are not on the main actor and
    /// there has to be one answer to what language a lecture is in — Apple's
    /// transcriber takes its locale from here too.
    nonisolated static let languageCode = "de-DE"

    /// How sure the voice-activity model has to be before a chunk is treated as
    /// speech, 0…1.
    ///
    /// **FluidAudio's own default is 0.85, and that is a bar for a microphone
    /// at your mouth.** A lecturer across a classroom, a question from the back
    /// row — none of it clears 85 % confidence on a built-in microphone, so it
    /// was gated out before the speech model ever saw it. The owner's report
    /// was that voices from further away simply do not appear.
    ///
    /// The cost of lowering it is the other kind of mistake: a cough, a chair,
    /// a corridor becomes a word. That is the better failure of the two here —
    /// a stray word in the live transcript is visible and ignorable, a sentence
    /// that was never shown is neither.
    ///
    /// **It gates the live transcript only.** The batch pass reads the whole
    /// file with no gate at all, so nothing said in the room is lost from the
    /// transcript of record because of this number.
    /// Lowered again, to 0.3, after 0.5 still dropped a voice the microphone
    /// was plainly picking up. The level meter moved and the words did not
    /// arrive, which is the clearest evidence there is that the gate and not
    /// the microphone was the problem.
    nonisolated static let speechThreshold: Float = 0.3

    /// How the gate decides an utterance is over.
    ///
    /// Passed explicitly because `processStreamingChunk` otherwise takes
    /// `VadSegmentationConfig.default`, whose 0.75 s of silence and 0.15
    /// hysteresis close a line on a cough. The report was precise: a short loud
    /// noise stopped the live transcript, and nothing arrived again until the
    /// room was clearly quiet and someone spoke clearly — twenty seconds of a
    /// lecture missing from the screen.
    ///
    /// Two numbers move, and only two of the nine here do anything at all in
    /// streaming mode — the streaming state machine reads `minSilenceDuration`,
    /// `speechPadding` and the negative threshold, and ignores
    /// `minSpeechDuration`, `maxSpeechDuration` and everything below them.
    /// Tuning those would be tuning nothing.
    ///
    /// - `negativeThresholdOffset` 0.2 puts the closing bar at 0.1 against an
    ///   opening bar of 0.3. Hysteresis: it takes far less confidence to keep a
    ///   line open than to open one, so a breath or a chair does not close it.
    /// - `minSilenceDuration` 1.2 s is how long it has to stay under that bar.
    ///   A cough is a tenth of a second and a pause between sentences is under
    ///   a second; both now pass through the middle of a line rather than
    ///   ending it.
    ///
    /// The upper bound on a line is `longestUtterance`, in `LiveTranscriber` —
    /// `maxSpeechDuration` here is one of the settings the streaming path never
    /// reads.
    nonisolated static let segmentation = VadSegmentationConfig(
        minSilenceDuration: 1.2,
        negativeThresholdOffset: 0.2
    )

    /// How long audio keeps reaching the speech model after the gate says the
    /// speech has stopped.
    ///
    /// The gate being wrong is not a rare event, and it is wrong in a
    /// particular way: a loud transient makes the microphone's automatic gain
    /// duck, and the speech that follows is quiet enough to sit under any
    /// threshold for several seconds until the gain comes back. No value of
    /// `speechThreshold` fixes that, because for those seconds the signal
    /// really is faint.
    ///
    /// So the gate no longer decides whether the model hears the lecture. It
    /// decides where a line ends, and the model keeps listening for three
    /// seconds past that point. If the voice comes back inside them — because
    /// it never actually left — the line simply continues and nothing is lost.
    /// The cost is three seconds of decoded silence per closed line, which on
    /// the Neural Engine is a fraction of a second of work.
    nonisolated static let speechHangover: TimeInterval = 3.0

    /// How much audio from before the gate opened is fed in with the first
    /// chunk of a line.
    ///
    /// Speech is recognised from having happened: the chunk that crosses the
    /// threshold is the one holding the first syllable, and the syllable before
    /// it is in the chunk already gone. Half a second of it is kept while the
    /// gate is shut so a line does not start mid-word.
    nonisolated static let speechPreRoll: TimeInterval = 0.5

    /// Chunk tier in milliseconds.
    ///
    /// FluidAudio's own note recommends 2240 ms and warns that 560 ms emits
    /// increasingly sparse punctuation over a long session. 1120 ms is the
    /// locked decision: it halves the lag between a sentence being said and
    /// appearing, which is what the live transcript is for, and it sits above
    /// the tier the punctuation warning is about.
    static let chunkMilliseconds = 1120

    private var loading: Task<Void, Never>?

    /// The three model sets, all present.
    ///
    /// A separate type so that anything which needs the models takes something
    /// that cannot be half-loaded, rather than three optionals it has to unwrap
    /// and then decide what to do about.
    struct Prepared: Sendable {
        let streaming: SharedNemotronMultilingualModels
        let batch: AsrModels
        let vad: VadManager
    }

    /// The models if all three are loaded, `nil` otherwise.
    var prepared: Prepared? {
        guard let streaming, let batch, let vad else { return nil }
        return Prepared(streaming: streaming, batch: batch, vad: vad)
    }

    // MARK: - Loading

    /// Downloads what is missing and loads everything. Safe to call again; a
    /// second call while the first is running joins it rather than starting a
    /// parallel download of the same files.
    func prepare() async {
        if case .ready = state { return }
        if let loading {
            await loading.value
            return
        }

        let task = Task { @MainActor in await load() }
        loading = task
        await task.value
        loading = nil
    }

    private func load() async {
        state = .downloading(0)

        do {
            // No `configuration:` argument, on purpose. See the type comment
            // and hard rule 4.
            let streaming = try await StreamingNemotronMultilingualAsrManager.downloadAndPreloadShared(
                languageCode: Self.languageCode,
                chunkMs: Self.chunkMilliseconds,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(progress.fractionCompleted)
                    }
                }
            )
            self.streaming = streaming

            let batch = try await AsrModels.downloadAndLoad(version: .v3)
            self.batch = batch

            let vad = try await VadManager(config: VadConfig(defaultThreshold: Self.speechThreshold))
            self.vad = vad

            state = .ready
        } catch {
            // The message reaches a dialog, so it is the error's own text and
            // never a stack trace or a file path.
            state = .failed(error.localizedDescription)
        }
    }

    /// Frees the models. Called when Retain has been idle long enough that
    /// holding three sets of weights resident is worse than reloading them.
    func unload() async {
        streaming = nil
        batch = nil
        vad = nil
        state = .notLoaded
    }
}
