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
/// - the **voice-activity** model, which says where the live transcript breaks
///   into lines. It does not gate the streaming model — see `LiveGate` for the
///   voice across the classroom that is why.
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

    /// How sure the voice-activity model has to be before it calls a chunk
    /// speech, 0…1.
    ///
    /// **This no longer decides what the speech model hears.** It decided that
    /// twice, at 0.85 and then at 0.3, and both times a lecturer across a
    /// classroom — plainly audible on the recording afterwards — never cleared
    /// the bar and never appeared in the live transcript. A distant voice is
    /// genuinely a faint signal, so there is no threshold that both admits it
    /// and still means anything. The gate was taken off the audio path
    /// instead; see `LiveGate`.
    ///
    /// What it still does is put the line breaks where the speech stops, which
    /// is what makes the transcript readable rather than a wall of twenty-
    /// second blocks. 0.3 is kept because getting that wrong now costs a line
    /// break in an odd place and nothing else.
    nonisolated static let speechThreshold: Float = 0.3

    /// How the model decides the speech in front of it has stopped.
    ///
    /// Passed explicitly because `processStreamingChunk` otherwise takes
    /// `VadSegmentationConfig.default`, whose 0.75 s of silence and 0.15
    /// hysteresis break a line on a cough.
    ///
    /// Only two of the nine settings here do anything in streaming mode — the
    /// streaming state machine reads `minSilenceDuration`, `speechPadding` and
    /// the negative threshold, and ignores `minSpeechDuration`,
    /// `maxSpeechDuration` and everything below them. Tuning those would be
    /// tuning nothing.
    ///
    /// - `negativeThresholdOffset` 0.2 puts the closing bar at 0.1 against an
    ///   opening bar of 0.3. Hysteresis: far less confidence is needed to keep
    ///   a line running than to start one.
    /// - `minSilenceDuration` 1.2 s is how long it has to stay under that bar.
    ///   A cough is a tenth of a second and a pause between sentences is under
    ///   a second; neither is a line break.
    nonisolated static let segmentation = VadSegmentationConfig(
        minSilenceDuration: 1.2,
        negativeThresholdOffset: 0.2
    )

    /// How long a line stays open after the model says the speech stopped.
    ///
    /// A loud transient makes the microphone's automatic gain duck, and the
    /// speech after it sits under any threshold for seconds until the gain
    /// comes back. Three seconds of doubt means a voice that returns inside
    /// them continues the same line rather than starting a new one.
    nonisolated static let speechHangover: TimeInterval = 3.0

    /// The longest anything runs before the line is closed and the decoder
    /// reset, whether the model ever called it speech or not.
    ///
    /// It is the upper bound on two different things. A line that never closes
    /// is a decoder that never resets, and a streaming RNN-T that has not been
    /// reset in ten minutes transcribes its own history rather than the room.
    /// And it is what puts a voice the model never flagged into the transcript
    /// at all: the audio was decoded either way, and this is when what came out
    /// is read off and shown. Anything that decoded to nothing is dropped, so
    /// during real silence the timer costs nothing.
    ///
    /// Twenty seconds is the ceiling on how late a line settles, not on how
    /// late the words appear — the partial callback puts those on the screen as
    /// they decode, whatever the gate thinks.
    ///
    /// **`maxSpeechDuration` in `segmentation` is not this.** FluidAudio reads
    /// that one in the batch segmenter only; nothing enforces a maximum while
    /// streaming, which is why this exists.
    nonisolated static let longestLine: TimeInterval = 20

    /// How far behind the present a line's start may sit while nothing has
    /// begun.
    ///
    /// Without it, a line after a long quiet stretch would be dated from the
    /// start of the quiet. With it, a line dated early and a line dated late
    /// because the speech in it was never flagged both stay inside three
    /// seconds. Live timestamps are provisional and the batch pass replaces
    /// them; this is about the transcript not reading as though the lecturer
    /// spoke half a minute before they did.
    nonisolated static let idleLineLag: TimeInterval = 3.0

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
