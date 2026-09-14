import Foundation
import Observation

/// One lecture, from the first second of audio to the finished transcript.
///
/// This is where the pieces meet: the recording engine writes the file and
/// forwards the audio, the live transcriber turns that into lines while the
/// lecture runs, and after it stops the batch pass replaces those lines with
/// the transcript of record.
///
/// The whole object is on the main actor because everything it holds is either
/// already there or reports back to it, and because it is what the interface
/// will bind to in phase 6.
@MainActor
@Observable
final class LectureSession {

    enum Phase: Equatable, Sendable {
        case idle
        /// First launch, roughly a gigabyte, once. How far it has got is
        /// `downloadFraction`.
        case preparingModels
        case recording
        /// The batch pass over the finished recording.
        case transcribing(Double)
        case separatingSpeakers(Double)
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// Finished lines. Provisional while the lecture runs, replaced wholesale
    /// when the batch pass lands.
    private(set) var lines: [TranscriptLine] = []

    /// The line currently forming. Empty between utterances.
    private(set) var partial = ""

    /// The recording on disk, once there is one.
    private(set) var recordingURL: URL?

    let recorder = RecordingEngine()
    let models = SpeechModels()

    /// How far the one-time model download has got, 0…1. Meaningful while
    /// `phase` is `.preparingModels`.
    ///
    /// Read back out of the models rather than copied into `phase`, so it is
    /// the download's own progress and not a number that was true once: `phase`
    /// changes when the lecture does, and the download reports far more often
    /// than that.
    var downloadFraction: Double {
        if case .downloading(let fraction) = models.state { return fraction }
        return 0
    }

    private var live: LiveTranscriber?

    /// Carries recorded blocks to the live transcriber in the order they were
    /// recorded, and lets `stop` wait until the last of them has been through.
    ///
    /// A `Task` per block would do neither. Tasks handed to an actor are not
    /// promised to run in the order they were made, so a lecture could reach
    /// the model slightly out of sequence — and nothing would hold `finish`
    /// back until the blocks the closing drain produced had arrived, which is
    /// exactly the last sentence of the lecture.
    private var feed: AsyncStream<[Float]>.Continuation?
    private var feeding: Task<Void, Never>?

    // MARK: - Running a lecture

    func start() async {
        switch phase {
        case .idle, .done, .failed:
            break
        case .preparingModels, .recording, .transcribing, .separatingSpeakers:
            return
        }

        lines = []
        partial = ""
        recordingURL = nil

        // The models come first: starting the recording and only then
        // discovering there is a gigabyte to fetch would mean the first
        // minutes of the lecture have no live transcript at all.
        if models.prepared == nil {
            phase = .preparingModels
            await models.prepare()
        }
        guard let prepared = models.prepared else {
            phase = .failed(String(localized: "Retain could not load the speech models.",
                                   comment: "A lecture could not start because the models are missing"))
            return
        }

        let live = await LiveTranscriber(models: prepared) { [weak self] update in
            Task { @MainActor [weak self] in self?.apply(update) }
        }
        self.live = live

        let (blocks, continuation) = AsyncStream<[Float]>.makeStream()
        feed = continuation
        // Detached, and at `.utility` like the writer queue that fills it: the
        // model is not main-actor work and a ninety-minute lecture of it has no
        // business on the thread that draws the interface.
        feeding = Task.detached(priority: .utility) {
            for await block in blocks {
                await live.append(block)
            }
        }
        recorder.onSamples = { continuation.yield($0) }

        let url = RecordingStore.newRecordingURL()
        await recorder.start(writingTo: url)

        guard recorder.state == .recording else {
            // Nothing was recorded, so nothing stays running: the transcriber
            // holds the streaming model, and a lecture that never began must
            // not keep a gigabyte of weights resident on the way out.
            await releaseLive()
            if case .failed(let message) = recorder.state {
                phase = .failed(message)
            } else {
                phase = .idle
            }
            return
        }

        recordingURL = url
        phase = .recording
    }

    /// Stops the recording and runs the pass that produces the transcript of
    /// record.
    func stop() async {
        guard phase == .recording else { return }

        // `finish` drains the writer one last time, so the blocks that close
        // the lecture are already in the stream by the time it returns and
        // `releaseLive` can wait for them.
        await recorder.finish()
        await releaseLive()
        partial = ""

        guard let url = recordingURL, let prepared = models.prepared else {
            phase = .done
            return
        }

        phase = .transcribing(0)

        let pass = LectureTranscription(models: prepared.batch)
        do {
            let output = try await pass.run(url) { [weak self] stage in
                Task { @MainActor [weak self] in
                    switch stage {
                    case .transcribing(let fraction): self?.phase = .transcribing(fraction)
                    case .separatingSpeakers(let fraction): self?.phase = .separatingSpeakers(fraction)
                    case .done: break
                    }
                }
            }

            lines = TranscriptAssembly.replacingProvisional(lines, with: output.lines)
            // Written beside the recording until phase 5 gives it a database.
            try? TranscriptSidecar.write(lines, for: url)
            phase = .done
        } catch {
            // The live transcript stays on screen: it is worse than the batch
            // pass, and it is very much better than an empty lecture.
            phase = .failed(String(localized: "Retain could not transcribe the recording.",
                                   comment: "The batch transcription pass failed"))
        }
    }

    // MARK: -

    /// Closes the feed, waits for every block already in it to reach the model,
    /// and lets the transcriber go.
    ///
    /// The order matters: finishing the stream first and only then awaiting the
    /// transcriber is what makes the last utterance of the lecture a line
    /// rather than audio that arrived after the model had been told there was
    /// no more.
    private func releaseLive() async {
        recorder.onSamples = nil
        feed?.finish()
        feed = nil
        await feeding?.value
        feeding = nil
        await live?.finish()
        live = nil
    }

    private func apply(_ update: LiveTranscriber.Update) {
        switch update {
        case .partial(let text):
            partial = text
        case .line(let line):
            lines.append(line)
            partial = ""
        }
    }
}
