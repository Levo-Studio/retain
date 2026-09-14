import FluidAudio
import Foundation

/// Re-transcribes the finished recording. This is the transcript of record.
///
/// Parakeet TDT v3 over the whole CAF, after the lecture, once. It is roughly
/// twice as accurate as the streaming pass — about 5.9 % word error on German
/// against 10 % — because it sees the whole utterance rather than 1120 ms of it
/// at a time, and because nothing has to keep up with real time.
///
/// **Everything downstream is built from this and never from the live pass.**
/// The notes, the search index, the chapter marks and the click-to-seek all
/// hang off the word timings this produces.
actor BatchTranscriber {

    enum Failure: Error, Sendable {
        case audioUnreadable
        case transcriptionFailed(String)
    }

    /// What one pass produced.
    struct Result: Sendable {
        let words: [WordTiming]
        let text: String
        /// Seconds of audio per second of wall clock. Under 1 means the pass is
        /// slower than the lecture was, which on a plugged-in Mac would be a
        /// defect worth seeing.
        let realTimeFactor: Double
    }

    private let models: AsrModels

    init(models: AsrModels) {
        self.models = models
    }

    /// Transcribes the whole recording.
    ///
    /// - Parameter progress: fraction 0…1. FluidAudio only reports progress for
    ///   audio longer than about fifteen seconds, so a short recording jumps
    ///   from nothing to done — which is honest rather than a fake ramp.
    func transcribe(
        _ url: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Result {
        let manager = AsrManager(models: models)
        let started = Date()

        // The progress stream has to be subscribed to before the call that
        // feeds it, or the early updates are gone before anyone is listening.
        let stream = await manager.transcriptionProgressStream
        let relay = progress.map { handler in
            Task {
                for try await fraction in stream {
                    handler(fraction)
                }
            }
        }
        defer { relay?.cancel() }

        let result: ASRResult
        do {
            // The decoder state is fresh for every recording, and it is made
            // inside the actor's own isolation because `transcribe` takes it
            // `inout`. Carrying one over between lectures would decode the next
            // one as a continuation of the last.
            result = try await manager.transcribeRecording(url)
        } catch {
            await manager.cleanup()
            throw Failure.transcriptionFailed(error.localizedDescription)
        }
        await manager.cleanup()

        let timings = result.tokenTimings ?? []
        let words = TokenMerge.words(
            from: timings.map { (token: $0.token, start: $0.startTime, end: $0.endTime) }
        )

        let elapsed = Date().timeIntervalSince(started)
        return Result(
            words: words,
            text: result.text,
            realTimeFactor: elapsed > 0 ? result.duration / elapsed : 0
        )
    }
}

// MARK: -

extension AsrManager {

    /// Transcribes one recording with a decoder state of its own.
    ///
    /// `transcribe` takes the state `inout`, which cannot cross an actor
    /// boundary, so the state is created and passed here — inside the manager's
    /// own isolation — rather than at the call site.
    fileprivate func transcribeRecording(_ url: URL) async throws -> ASRResult {
        // Two decoder layers is TdtDecoderState's own default and matches the
        // v3 models; the initialiser throws if it cannot allocate them.
        var state = try TdtDecoderState(decoderLayers: decoderLayerCount)
        return try await transcribe(url, decoderState: &state, language: .german)
    }
}
