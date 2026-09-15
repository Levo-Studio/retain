import Foundation
import Observation

/// Everything boards 03 and 04 are drawn from, for one recording.
///
/// One model behind both tabs rather than one each, because they are one
/// window: the chrome, the meta strip and the rail are the same on both, and
/// the rail's chat has to survive switching to the transcript and back.
@Observable
final class RecordingDetailModel {

    /// The two tabs under the meta strip.
    nonisolated enum Tab: Hashable, Sendable, CaseIterable {
        case notes
        case transcript
    }

    /// What the right-hand rail is showing. Board 03 opens on Chapters and
    /// board 04 on Chat, which is a default per tab and not a rule: the segment
    /// is there to be changed.
    nonisolated enum Rail: Hashable, Sendable, CaseIterable {
        case chapters
        case chat
    }

    // MARK: - What was loaded

    private(set) var recording: Recording
    private(set) var course: Course?
    private(set) var term: Term?

    private(set) var blocks: [NoteBlock] = []
    private(set) var lines: [TranscriptLine] = []
    private(set) var annotations: [Annotation] = []

    /// Keyed by block number, already turned into ranges the renderer paints.
    private(set) var highlightRanges: [Int: [Range<Int>]] = [:]

    private(set) var isLoading = false

    // MARK: - What the user is doing

    var tab: Tab = .notes {
        didSet {
            guard tab != oldValue else { return }
            // The rail follows the tab the first time each is opened, the way
            // the boards draw them, and stays wherever the user last put it
            // after that.
            if !hasChosenRail { rail = tab == .notes ? .chapters : .chat }
        }
    }

    var rail: Rail = .chapters {
        didSet { if rail != oldValue { hasChosenRail = true } }
    }

    private var hasChosenRail = false

    /// Board 03's field above the segment: "Search notes and transcript …".
    var railQuery = ""

    /// Board 04's find bar over the transcript.
    var findQuery = "" {
        didSet {
            guard findQuery != oldValue else { return }
            find = TranscriptFind(lines: lines, query: findQuery)
        }
    }

    private(set) var find = TranscriptFind()

    // MARK: - Where the window is pointed

    /// The last thing the window was asked to bring into view.
    ///
    /// The two panes watch it and scroll. It is a request rather than a
    /// position because the panes are scrolled by the reader as well, and the
    /// model has no business believing it knows where they are.
    private(set) var reveal: DetailReveal.Request?

    /// Counts the requests, so that asking for the same place twice is two
    /// requests. See `DetailReveal.Request`.
    private var revealCount = 0

    /// The block the chapter rail draws the accent rule on.
    private(set) var currentBlockNumber: Int?

    // MARK: - The chat

    /// Handed in rather than built here: the conversation needs a language
    /// model, and which one that is belongs to settings.
    private var chat: RecordingChat?

    private(set) var turns: [ChatTurn] = []
    private(set) var isAnswering = false
    private(set) var chatFailure: String?

    var question = ""

    // MARK: -

    private let database: RetainDatabase

    /// - Parameter chat: handed in by a test that wants to answer without a
    ///   server. `nil` in the app, where `load()` builds one from Settings —
    ///   see `ChatFactory`, and the reason it has to.
    init(recording: Recording, database: RetainDatabase, chat: RecordingChat? = nil) {
        self.recording = recording
        self.database = database
        self.chat = chat
        wasChatHandedIn = chat != nil
    }

    /// So `load()` does not replace a chat a test gave it.
    private let wasChatHandedIn: Bool


    // MARK: - Writing the notes after the fact

    /// Where a run of the summariser over a finished recording has got to.
    nonisolated enum NoteWriting: Equatable, Sendable {
        case idle
        case running(done: Int, total: Int)
        /// What went wrong, in the error's own words.
        case failed(String)
    }

    private(set) var noteWriting: NoteWriting = .idle

    /// Whether the button that writes them is offered at all.
    ///
    /// Only for a recording that has a transcript and **no notes**. Rewriting
    /// notes that already exist is a different action with a different cost:
    /// the highlights a reader marked hang off the blocks, and replacing the
    /// blocks would take the highlights with them. That needs its own
    /// confirmation, and it is not this.
    var canWriteNotes: Bool {
        guard blocks.isEmpty, !lines.isEmpty else { return false }
        if case .running = noteWriting { return false }
        return true
    }


    /// What writing the notes again would cost. See `ReanalysisImpact`.
    var reanalysisImpact: ReanalysisImpact {
        ReanalysisImpact(
            noteBlocks: blocks.count,
            highlights: highlightRanges.values.reduce(0) { $0 + $1.count },
            transcriptLines: lines.count
        )
    }

    /// Whether the title bar's button can be pressed at all.
    ///
    /// Drawn always — it sits beside Export and a control that comes and goes
    /// from a title bar is a control nobody can find twice — and unavailable
    /// while a run is in flight or there is no transcript to read.
    var canReanalyse: Bool {
        guard reanalysisImpact.canRun else { return false }
        if case .running = noteWriting { return false }
        return true
    }

    /// Throws the notes away and writes them again from the transcript.
    ///
    /// The blocks go first, in one write, which takes the highlights with them
    /// — that is what the confirmation is for. Then the same run as
    /// `writeNotes`, which is why that is where the work lives.
    func reanalyse() async {
        guard canReanalyse, let recordingID = recording.id else { return }

        do {
            try await NoteRepository(database).replaceBlocks([], for: recordingID)
        } catch {
            noteWriting = .failed(SettingsModel.message(for: error))
            return
        }

        blocks = []
        highlightRanges = [:]
        await writeNotes()
    }

    /// Runs the summariser over the stored transcript and writes the notes.
    ///
    /// **This exists because the notes could silently never arrive.** The
    /// summaries are made during the lecture, one block at a time; a block the
    /// model could not answer was marked as waiting, and the comment beside it
    /// said summaries are caught up when the connection is back. Nothing caught
    /// them up. A lecture recorded while LM Studio was unreachable — or, as it
    /// happened, while its API key had been deleted — ended with a full
    /// transcript, no notes, and a window that said only that the notes had not
    /// been written yet.
    ///
    /// It stops at the first failure rather than working through the rest. A
    /// server that refused one block refuses the next, and a queue of identical
    /// errors is not more informative than one.
    func writeNotes() async {
        guard canWriteNotes, let recordingID = recording.id else { return }

        guard let summarizer = SummarizerFactory.make() else {
            noteWriting = .failed(
                String(localized: "No model is chosen. Pick one in Settings under Local language model.",
                       comment: "Why the notes cannot be written: no model has been chosen in settings")
            )
            return
        }

        // The same boundaries the lecture would have used, with `finished` —
        // the recording is over, so the trailing block is whole rather than
        // still filling.
        let blocksToWrite = BlockBoundaries.blocks(from: lines, markers: markers, finished: true)
        guard !blocksToWrite.isEmpty else { return }

        noteWriting = .running(done: 0, total: blocksToWrite.count)
        let repository = NoteRepository(database)

        for (index, block) in blocksToWrite.enumerated() {
            do {
                let written = try await summarizer.summarise(block)
                let stored = StoredNoteBlock(
                    recordingID: recordingID,
                    position: written.number,
                    startTime: written.start,
                    endTime: written.end,
                    markdown: written.markdown
                )
                _ = try await repository.append(stored, to: recordingID)
                blocks.append(written)
                noteWriting = .running(done: index + 1, total: blocksToWrite.count)
            } catch {
                noteWriting = .failed(SettingsModel.message(for: error))
                return
            }
        }

        noteWriting = .idle
    }

    // MARK: - Loading

    func load() async {
        guard let recordingID = recording.id else { return }
        isLoading = true
        defer { isLoading = false }

        let library = LibraryRepository(database)
        let transcripts = TranscriptRepository(database)
        let notes = NoteRepository(database)

        do {
            let stored = try await notes.blocks(for: recordingID)
            let highlights = try await notes.highlights(for: recordingID)

            blocks = Self.noteBlocks(from: stored)
            highlightRanges = Self.highlightRanges(of: highlights, in: stored)
            lines = try await transcripts.lines(for: recordingID)
            annotations = try await transcripts.annotations(for: recordingID)

            self.course = try await library.course(recording.courseID)
            // The recording's own term, not the course's: a course runs in
            // several, and this window is about one lesson — the half-year it
            // was recorded in, whatever the course has been used for since.
            term = try await library.term(recording.termID)
        } catch {
            // A read that failed leaves the window empty rather than wrong.
            // There is no error state drawn for the detail window, and a
            // half-loaded transcript would be worse than none.
            blocks = []
            lines = []
            annotations = []
        }

        find = TranscriptFind(lines: lines, query: findQuery)

        let material = RecordingChat.Material(
            notes: self.notes,
            transcript: lines,
            isRecording: recording.state == .recording
        )

        // Built here rather than by the caller. It used to be the caller's job
        // and no caller did it: `RecordingChat(` appeared nowhere in the app, so
        // every window got `nil` and asking a question did nothing, silently.
        if !wasChatHandedIn {
            chat = ChatFactory.make(material: material)
        }

        if let chat {
            await chat.update(material)
            turns = await chat.turns
        }
    }

    /// The stored rows as the cards the rest of the app speaks in.
    ///
    /// `position` is zero-based in the store and `number` is one-based
    /// everywhere else — it is what a chat answer means by "Note 3" — so the
    /// conversion happens here and nowhere else.
    static func noteBlocks(from stored: [StoredNoteBlock]) -> [NoteBlock] {
        stored.enumerated().map { index, block in
            NoteBlock(
                number: index + 1,
                markdown: block.markdown,
                start: block.startTime,
                end: block.endTime,
                state: .written
            )
        }
    }

    static func highlightRanges(
        of highlights: [Highlight],
        in stored: [StoredNoteBlock]
    ) -> [Int: [Range<Int>]] {
        var ranges: [Int: [Range<Int>]] = [:]
        for (index, block) in stored.enumerated() {
            let mine = highlights.filter { $0.noteBlockID == block.id }
            guard !mine.isEmpty else { continue }
            ranges[index + 1] = NoteHighlightAnchoring.ranges(of: mine, in: block.markdown)
        }
        return ranges
    }

    // MARK: - Derived

    /// Markers and annotations are the same rows read two ways: the chapter
    /// rail wants the times, the notes want the text.
    var markers: [RecordingMarker] {
        annotations.map { RecordingMarker(time: $0.time, text: $0.note ?? "") }
    }

    var notes: RecordingNotes {
        RecordingNotes(
            topic: recording.topic,
            markdown: blocks.map(\.markdown).joined(separator: "\n\n"),
            blocks: blocks,
            markers: markers
        )
    }

    /// The chapter rail.
    ///
    /// **One level.** Board 03 draws two — headings and indented sub-entries —
    /// and only the headings exist: a chapter is a note block's heading, and a
    /// block has exactly one. There is nothing under it to indent.
    var chapters: [NoteChapter] {
        NoteChapters.entries(from: blocks, markers: markers)
    }

    /// The rail's field filters the rail. A chapter stays if the query is in
    /// its card or in the transcript under it, which is what "Search notes and
    /// transcript" means from a rail that is a list of chapters.
    var filteredChapters: [NoteChapter] {
        let query = railQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chapters }

        return chapters.filter { chapter in
            guard let block = blocks.first(where: { $0.number == chapter.blockNumber }) else { return false }
            if block.markdown.localizedStandardContains(query) { return true }
            return lines.contains {
                $0.start >= block.start && $0.start <= block.end && $0.text.localizedStandardContains(query)
            }
        }
    }

    var noteItems: [NoteItem] {
        NotesComposition.items(blocks: blocks, annotations: annotations)
    }

    var chatAvailability: ChatAvailability {
        ChatAvailability.of(
            isRecording: recording.state == .recording,
            hasNotes: recording.state == .done
        )
    }

    /// The chapter the accent rule sits on: wherever the window was last taken,
    /// and the first one before it has been taken anywhere. Board 03 draws
    /// exactly one row picked out, and never none.
    var currentChapter: NoteChapter? {
        let chapters = self.chapters
        return chapters.first { $0.blockNumber == currentBlockNumber } ?? chapters.first
    }

    var markerCount: Int { annotations.count }

    // MARK: - Moving around the window

    /// A chapter row.
    ///
    /// The rail is a list of places in the notes, so a row brings the notes
    /// forward at its block. That is what a chapter rail is for, and it is all
    /// it can be now: there is no audio to start playing at that minute.
    func show(chapter: NoteChapter) {
        request(.block(chapter.blockNumber))
    }

    /// Opens the recording at a moment somebody arrived from — a search hit in
    /// the library, which carries the second it matched at.
    ///
    /// The transcript comes forward with it: a search result is a sentence, and
    /// landing in the notes is not where they asked to go.
    ///
    /// The name is the one the library calls. Nothing seeks any more; what this
    /// does is scroll the line that second was said in into view.
    func seek(to time: TimeInterval) {
        guard let id = DetailReveal.line(at: time, in: lines) else {
            // A recording whose transcript is empty still opens, on the tab the
            // search hit came from, rather than silently staying on the notes.
            tab = .transcript
            return
        }
        request(.line(id))
    }

    /// A source chip under a chat answer.
    func follow(_ reference: ChatReference) {
        guard let target = DetailReveal.target(for: reference, lines: lines, blocks: blocks) else { return }
        request(target)
    }

    /// The one place the window is pointed somewhere, so the tab, the rail's
    /// accent rule and the pane that has to scroll can never disagree about
    /// where that is.
    private func request(_ target: DetailReveal.Target) {
        revealCount += 1
        reveal = DetailReveal.Request(target: target, ordinal: revealCount)

        switch target {
        case let .line(id):
            tab = .transcript
            // The rail follows the reader: the chapter the line falls under is
            // the one worth picking out while they are reading it.
            if let line = lines.first(where: { $0.id == id }) {
                currentBlockNumber = DetailReveal.block(at: line.start, in: blocks) ?? currentBlockNumber
            }
        case let .block(number):
            tab = .notes
            currentBlockNumber = number
        }
    }

    // MARK: - The find bar

    func findNext() {
        find.moveToNext()
    }

    func findPrevious() {
        find.moveToPrevious()
    }

    /// The line the pane should bring into view, if any.
    var lineToScrollTo: TranscriptLine? {
        guard let match = find.currentMatch, lines.indices.contains(match.lineIndex) else { return nil }
        return lines[match.lineIndex]
    }

    // MARK: - Asking

    func ask() async {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, let chat, chatAvailability == .ready, !isAnswering else { return }

        question = ""
        chatFailure = nil
        isAnswering = true
        defer { isAnswering = false }

        // **Shown before the request, not after it.** The comment here used to
        // say the question appears the moment it is sent, and it did not:
        // `turns` was read back only once the answer had arrived, so typing a
        // question and pressing Return produced nothing at all for as long as
        // the model took. A local turn goes up now and the actor's own list
        // replaces it when the answer lands.
        turns.append(ChatTurn(author: .you, text: asked))

        do {
            _ = try await chat.ask(asked)
            turns = await chat.turns
        } catch {
            turns = await chat.turns
            chatFailure = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "The model could not answer.", comment: "Shown in the chat rail when a question failed for a reason with no message of its own")
        }
    }
}
