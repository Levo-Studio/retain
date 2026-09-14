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

    /// The course this lecture belongs to, picked in the popover before the
    /// microphone opens. A recording belongs to exactly one course, so there is
    /// no lecture without one.
    private(set) var course: Course?

    /// The term the lecture is being recorded in — the one that was current
    /// when the microphone opened.
    ///
    /// Held for the length of the lecture rather than read back when the row is
    /// written: somebody who changes the current term in the library window
    /// halfway through a lesson has not moved the lesson they are sitting in.
    private(set) var term: Term?

    /// The row the lecture is being written into, once there is a database and
    /// a course. `nil` in a session built without a store.
    private(set) var recordingID: Int64?

    /// When the microphone opened. What board 01's meta strip draws under
    /// "Date", and what a recording is identified by — there is no lecture
    /// number and nothing to name.
    private(set) var startedAt = Date.now

    /// The topic, once a model has read it out of the transcript.
    ///
    /// Nil for the whole lecture, which is why the meta strip's value is empty
    /// while one is running: the topic comes out of the reduce over the
    /// finished transcript, and there is nothing honest to put there before it.
    private(set) var topic: String?

    /// Everything the user marked with `⌘⇧M`, in the order they marked it.
    private(set) var markers: [RecordingMarker] = []

    /// The note cards written while the lecture runs, one per closed block.
    ///
    /// A card appears the moment its block closes, in `.summarising`, and is
    /// replaced when the model answers — which is what board 01 draws as the
    /// dim block with "writing …" beside its heading.
    private(set) var notes: [NoteBlock] = []

    /// What turns a closed block into a card.
    ///
    /// **Nothing sets it yet.** It needs an LM Studio address and the name of a
    /// model, and both of those are settings — board 06 — which is where the
    /// user picks them. Until that pane exists there is nothing to summarise
    /// with, and `notes` stays empty rather than filling with placeholders for
    /// cards that are never going to arrive.
    /// What turns a closed block into a note card.
    ///
    /// Rebuilt from Settings at the start of every lecture rather than held,
    /// because the address, the model and whether LM Studio is running at all
    /// can each have changed since the last one. `nil` is the ordinary state of
    /// a fresh install: the lecture records and transcribes, and the notes
    /// column stays empty until somebody has been to Settings.
    var summarizer: RecordingSummarizer?

    /// Whether the microphone is closed while the lecture stays open.
    ///
    /// A pause is not a phase: the file, the transcriber and the block
    /// boundaries all stay exactly where they were, and the only thing that
    /// stops is the audio going in.
    var isPaused: Bool { recorder.state == .paused }

    let recorder = RecordingEngine()
    let models = SpeechModels()

    /// Where the lecture is written down. `nil` in previews and in tests that
    /// only care about what the interface does with a phase.
    private let store: LectureStore?

    init(store: LectureStore? = nil) {
        self.store = store
    }

    /// A session holding what a lecture in progress would hold, without one.
    ///
    /// It opens no microphone, loads no model and writes nothing down. It
    /// exists because board 01 cannot otherwise be looked at: every way of
    /// getting a transcript line onto that screen for real runs through a
    /// gigabyte of weights and somebody talking for three minutes, and a screen
    /// that can only be seen that way is a screen nobody checks against the
    /// export.
    init(
        course: Course,
        lines: [TranscriptLine] = [],
        partial: String = "",
        markers: [RecordingMarker] = [],
        notes: [NoteBlock] = [],
        topic: String? = nil,
        startedAt: Date = .now
    ) {
        store = nil
        self.course = course
        self.lines = lines
        self.partial = partial
        self.markers = markers
        self.notes = notes
        self.topic = topic
        self.startedAt = startedAt
    }

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

    /// Opens the microphone for one course, in one term.
    ///
    /// Both are taken rather than chosen here: they are what the recording row
    /// hangs off, and the popover has already asked for both. Nothing in Retain
    /// records into no course, and nothing records into no term.
    func start(in course: Course, during term: Term) async {
        switch phase {
        case .idle, .done, .failed:
            break
        case .preparingModels, .recording, .transcribing, .separatingSpeakers:
            return
        }

        // A term that was never written has no id, and a recording carries its
        // term as an id. The library filters on that column, so an invented or
        // borrowed one would file the lecture under a half-year it did not
        // happen in — quietly, and for good. Refusing is the honest answer, and
        // it is said out loud rather than by recording into nowhere.
        guard term.id != nil else {
            phase = .failed(String(localized: "Retain has no current term to record into.",
                                   comment: "A lecture could not start because no term is marked as the current one"))
            return
        }

        lines = []
        partial = ""
        recordingURL = nil
        recordingID = nil
        markers = []

        // Built here rather than held from launch: the address, the model and
        // whether LM Studio is running at all can each have changed since the
        // last lecture, and a summariser made at launch would be answering to
        // whatever was true then. Nil is fine — see the property.
        summarizer = SummarizerFactory.make()
        notes = []
        topic = nil
        startedAt = .now
        self.course = course
        self.term = term

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
        // The row is opened only once audio is actually flowing. A row written
        // before `recorder.start` would survive a microphone that never opened
        // as a recording of nothing, and the library would show it.
        if let store, let courseID = course.id, let termID = term.id {
            recordingID = try? await store.library.startRecording(
                in: courseID,
                during: termID,
                filename: url.lastPathComponent
            ).id
        }
        phase = .recording
    }

    /// Holds the microphone. Everything else about the lecture stays open.
    func pause() {
        guard phase == .recording else { return }
        recorder.pause()
    }

    /// What `⌘⇧P` does, and the "Resume" button with it.
    func resume() {
        guard phase == .recording else { return }
        recorder.resume()
    }

    /// Moves a running lecture to another course — the chevron board 01 draws
    /// beside the course in the meta strip.
    ///
    /// The row moves with it. A recording belongs to exactly one course, so
    /// picking a different one is not a label change: it is where the recording
    /// will be found in the library afterwards.
    func changeCourse(to course: Course) {
        guard self.course?.id != course.id else { return }
        self.course = course

        guard let store, let recordingID, let courseID = course.id else { return }
        Task {
            if var recording = try? await store.library.recording(recordingID) {
                recording.courseID = courseID
                _ = try? await store.library.save(recording)
            }
        }
    }

    /// What `⌘⇧M` produces: a line the user typed, at the second they typed it.
    ///
    /// The text goes to the model with the block it falls in, which is why the
    /// marker is recorded before the block boundaries are asked again — a
    /// marker that arrives after its own block has closed would be summarised
    /// into the next one.
    func addMarker(_ text: String) {
        guard phase == .recording else { return }

        let marker = RecordingMarker(time: recorder.duration, text: text)
        markers.append(marker)

        if let store, let recordingID {
            Task {
                _ = try? await store.transcript.annotate(
                    at: marker.time,
                    note: marker.hasText ? marker.text : nil,
                    in: recordingID
                )
            }
        }

        closeBlocks()
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
            await write(lines, state: .done)
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
            await write(lines, state: .done)

            // Everything that ever had to read the audio has read it: the batch
            // pass and the diarization inside `pass.run`, and the transcript is
            // written. Retain keeps the transcript, not the recording — see
            // `TransientAudio`, which deletes nothing whose transcript is not
            // stored, so the `catch` below still leaves its file on disk.
            if let store, let recordingID {
                await TransientAudio(store.database).discardAudio(of: recordingID, passFinished: true)
            }

            phase = .done
        } catch {
            // The recording itself is not lost because the pass over it failed,
            // so the row is closed with the live lines rather than left saying
            // it is still recording for ever.
            await write(lines, state: .done)
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

            if let store, let recordingID {
                // One insert per finished line, not a batch at the end: the
                // line is already on screen, and the write is what makes it
                // survive a crash in the middle of a lecture.
                Task { _ = try? await store.transcript.append(line, to: recordingID) }
            }

            closeBlocks()
        }
    }

    // MARK: - Note blocks

    /// Cuts the transcript so far into blocks and summarises any that have just
    /// closed.
    ///
    /// `finished: false`, always: the trailing block is still filling, and
    /// closing it would send half a topic to the model and put a card in the
    /// notes that the next card then repeats.
    private func closeBlocks() {
        guard let summarizer else { return }

        let blocks = BlockBoundaries.blocks(from: lines, markers: markers, finished: false)

        for block in blocks where !notes.contains(where: { $0.number == block.number }) {
            notes.append(
                NoteBlock(
                    number: block.number,
                    markdown: "",
                    start: block.start,
                    end: block.end,
                    state: .summarising
                )
            )

            Task { [weak self] in
                let written = try? await summarizer.summarise(block)
                await MainActor.run { self?.replaceNote(block.number, with: written) }
            }
        }
    }

    /// Puts the model's card in place of the placeholder, or marks the block as
    /// waiting if the model could not be reached.
    ///
    /// `deferred` rather than dropping the card: board 07's "No connection"
    /// dialog says summaries are caught up once the connection is back, and a
    /// block that silently vanished could not be.
    private func replaceNote(_ number: Int, with written: NoteBlock?) {
        guard let index = notes.firstIndex(where: { $0.number == number }) else { return }

        if let written {
            notes[index] = written
            if let store, let recordingID {
                let block = StoredNoteBlock(
                    recordingID: recordingID,
                    position: written.number,
                    startTime: written.start,
                    endTime: written.end,
                    markdown: written.markdown
                )
                Task { _ = try? await store.notes.append(block, to: recordingID) }
            }
        } else {
            notes[index].state = .deferred
        }
    }

    // MARK: - Writing the lecture down

    /// Closes the recording row and replaces its transcript in one go.
    ///
    /// Nothing happens without a store or without a row, which is every session
    /// a test or a preview builds.
    private func write(_ lines: [TranscriptLine], state: RecordingState) async {
        guard let store, let recordingID else { return }

        try? await store.transcript.replaceLines(lines, for: recordingID)

        if var recording = try? await store.library.recording(recordingID) {
            recording.duration = recorder.duration
            recording.state = state
            _ = try? await store.library.save(recording)
        }
    }
}
