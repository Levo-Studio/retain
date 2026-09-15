import FluidAudio
import Foundation

/// The pass that runs after the lecture and produces the transcript of record.
///
/// Three steps, in this order and for this reason:
///
/// 1. **Batch transcription** of the whole recording. Twice as accurate as the
///    live pass, and the only source of word-level timings — which is what puts
///    the right second beside each line.
/// 2. **Diarization** over the same file. Offline, because clustering has to
///    have heard every voice before it can decide how many there are.
/// 3. **Assembly**, which is pure and lives in the pipeline: words plus speaker
///    segments become the lines the transcript is read as.
///
/// Transcription first and diarization second, not in parallel: both are heavy
/// Neural Engine work, and running them at once on a laptop makes each slower
/// while drawing more power than running them in turn. There is nothing to wait
/// for — the lecture is over.
///
/// These two steps are the last things that ever read the file. What deletes it
/// afterwards is `TransientAudio`, called by `LectureSession` once this pass has
/// returned and its transcript has been written.
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

    // MARK: - Which transcriber

    /// Apple's model where the Mac has it, Parakeet everywhere else.
    ///
    /// `SpeechAnalyzer` ships in macOS 26 and Retain's deployment target is 15,
    /// so this is a choice made at run time rather than a dependency swapped
    /// out. Both produce the same thing — words with times — and everything
    /// after this point is the same code.
    ///
    /// Apple's is preferred where it exists because it had the lowest German
    /// word error rate of the engines in a 2026 benchmark over 13 000
    /// recordings. Whether that holds for a classroom rather than read-aloud
    /// speech is a question the owner's own recordings answer, and Parakeet is
    /// one line away.
    ///
    /// **A failure falls back rather than failing the lecture.** A model asset
    /// that will not download, a locale the system has dropped — none of that
    /// is a reason to lose an hour of audio that Parakeet can read.
    private func transcribe(
        _ url: URL,
        onStage: (@Sendable (Stage) -> Void)?
    ) async throws -> BatchTranscriber.Result {
        if #available(macOS 26.0, *), await AppleSpeechTranscriber.isUsable() {
            do {
                let apple = try await AppleSpeechTranscriber().transcribe(url) { fraction in
                    onStage?(.transcribing(fraction))
                }
                if !apple.words.isEmpty {
                    return BatchTranscriber.Result(
                        words: apple.words,
                        text: apple.text,
                        realTimeFactor: apple.realTimeFactor
                    )
                }
            } catch {
                // Fall through to Parakeet. Deliberately silent: the user is
                // not waiting on a choice between two transcribers, and the one
                // that works is about to run.
            }
        }

        let transcriber = BatchTranscriber(models: models)
        return try await transcriber.transcribe(url) { fraction in
            onStage?(.transcribing(fraction))
        }
    }

    func run(
        _ url: URL,
        onStage: (@Sendable (Stage) -> Void)? = nil
    ) async throws -> Output {
        let transcription = try await transcribe(url, onStage: onStage)

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
