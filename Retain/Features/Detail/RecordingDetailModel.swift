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

    let player = RecordingPlayer()

    // MARK: - The chat

    /// Handed in rather than built here: the conversation needs a language
    /// model, and which one that is belongs to settings.
    private let chat: RecordingChat?

    private(set) var turns: [ChatTurn] = []
    private(set) var isAnswering = false
    private(set) var chatFailure: String?

    var question = ""

    // MARK: -

    private let database: RetainDatabase

    init(recording: Recording, database: RetainDatabase, chat: RecordingChat? = nil) {
        self.recording = recording
        self.database = database
        self.chat = chat
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

            if let course = try await library.course(recording.courseID) {
                self.course = course
                term = try await library.term(course.termID)
            }
        } catch {
            // A read that failed leaves the window empty rather than wrong.
            // There is no error state drawn for the detail window, and a
            // half-loaded transcript would be worse than none.
            blocks = []
            lines = []
            annotations = []
        }

        find = TranscriptFind(lines: lines, query: findQuery)
        player.load(filename: recording.filename)

        if let chat {
            await chat.update(
                RecordingChat.Material(
                    notes: self.notes,
                    transcript: lines,
                    isRecording: recording.state == .recording
                )
            )
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

    /// The chapter the accent rule sits on: the one playback is inside, and the
    /// first one before anything has been played. Board 03 draws exactly one
    /// row picked out, and never none.
    var currentChapter: NoteChapter? {
        let chapters = self.chapters
        return chapters.last { $0.time <= player.time } ?? chapters.first
    }

    var markerCount: Int { annotations.count }

    var duration: TimeInterval? { recording.duration > 0 ? recording.duration : nil }

    // MARK: - Jumping

    func play(line: TranscriptLine) {
        player.seek(to: DetailSeek.target(forLineStartingAt: line.start, duration: duration))
    }

    func play(chapter: NoteChapter) {
        player.seek(to: DetailSeek.target(forChapterAt: chapter.time, duration: duration))
    }

    /// A source chip under a chat answer. A transcript chip also brings the
    /// transcript tab forward — jumping into audio the user cannot see the
    /// words of is half an answer.
    func follow(_ reference: ChatReference) {
        guard let target = DetailSeek.target(for: reference, blocks: blocks, duration: duration) else { return }
        if case .transcript = reference { tab = .transcript }
        player.seek(to: target)
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

        // The question shows in the rail the moment it is sent: the actor has
        // already appended it, and the answer can take a small model a while.
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
