import FluidAudio
import Foundation

/// The pass that runs after the lecture and produces the transcript of record.
///
/// Three steps, in this order and for this reason:
///
/// 1. **Batch transcription** of the whole recording. Twice as accurate as the
///    live pass, and the only source of word-level timings — which is what
///    makes clicking a line seek to the right second.
/// 2. **Diarization** over the same file. Offline, because clustering has to
///    have heard every voice before it can decide how many there are.
/// 3. **Assembly**, which is pure and lives in the pipeline: words plus speaker
///    segments become the lines the transcript is read as.
///
/// Transcription first and diarization second, not in parallel: both are heavy
/// Neural Engine work, and running them at once on a laptop makes each slower
/// while drawing more power than running them in turn. There is nothing to wait
/// for — the lecture is over.
actor LectureTranscription {

    struct Output: Sendable {
        let lines: [TranscriptLine]
        /// The transcript as one string, for the summariser and for search.
        let text: String
        /// Whether speaker separation actually ran. False on macOS 14, where
        /// diarization is not available — see `SpeakerDiarizer`.
        let hasSpeakers: Bool
        let realTimeFactor: Double
    }

    /// Where the pass has got to. The popover's "Summarizing" state draws this.
    enum Stage: Sendable {
        case transcribing(Double)
        case separatingSpeakers(Double)
        case done
    }

    private let models: AsrModels

    init(models: AsrModels) {
        self.models = models
    }

    func run(
        _ url: URL,
        onStage: (@Sendable (Stage) -> Void)? = nil
    ) async throws -> Output {
        let transcriber = BatchTranscriber(models: models)
        let transcription = try await transcriber.transcribe(url) { fraction in
            onStage?(.transcribing(fraction))
        }

        let diarizer = SpeakerDiarizer()
        let segments = await diarizer.segments(for: url) { fraction in
            onStage?(.separatingSpeakers(fraction))
        }

        let lines = TranscriptAssembly.lines(from: transcription.words, segments: segments)
        onStage?(.done)

        return Output(
            lines: lines,
            text: transcription.text,
            hasSpeakers: !segments.isEmpty,
            realTimeFactor: transcription.realTimeFactor
        )
    }
}
