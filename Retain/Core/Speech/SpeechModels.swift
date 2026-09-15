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

            let vad = try await VadManager()
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
