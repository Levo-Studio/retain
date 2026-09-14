import Foundation

/// Something the user marked while the recording was running.
///
/// `⌘⇧M` opens a composer rather than dropping a bare pin — the design draws
/// "Anmerkung — geht an die KI" and the typed text appears in the notes as
/// "Von dir · 00:46:41". An empty `text` is therefore a legitimate marker, not
/// an invalid one: the user hit the hotkey and did not type anything.
///
/// Not to be confused with a **highlight**, which is the user marking a passage
/// of the finished notes. A marker is an input to the model; a highlight is
/// something the user made afterwards out of what the model wrote.
nonisolated struct RecordingMarker: Identifiable, Hashable, Sendable, Codable {

    let id: UUID

    /// Seconds from the start of the recording, like every other time in
    /// Retain. The recording is the timeline.
    var time: TimeInterval

    var text: String

    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(id: UUID = UUID(), time: TimeInterval, text: String = "") {
        self.id = id
        self.time = time
        self.text = text
    }
}

// MARK: - Note blocks

/// Where a note block stands.
///
/// The design draws the open block dim, with "schreibt …" beside the heading
/// and a caret in the paragraph. `deferred` is the other half of the "No
/// connection" dialog — "Recording continues; summaries are caught up once the
/// connection is back" — and exists so a block that has no summary yet is
/// visibly waiting rather than silently missing.
nonisolated enum NoteBlockState: Hashable, Sendable, Codable {
    case summarising
    case written
    case deferred
}

/// One numbered note card, written while the recording is still running.
///
/// A block summarises **only its own stretch**. That is what makes a card
/// appear within seconds of a block closing instead of at the end of the hour,
/// and it is why the small model is enough for it: three minutes of one topic
/// is a job a 3–8B model can do.
nonisolated struct NoteBlock: Identifiable, Hashable, Sendable, Codable {

    /// One-based. The design draws it zero-padded to two digits ("01"), and it
    /// is what a chat answer means when it cites "Notiz 3".
    let number: Int

    /// The card, as **Markdown**.
    ///
    /// The model writes Markdown rather than a heading, a paragraph and a list
    /// in separate fields. Two reasons, and the first is the one that decides
    /// it: writing prose with emphasis in it is what a language model is good
    /// at, while filling four fields in a fixed order is what it is bad at —
    /// the same 7B model that produces a clean paragraph will put the heading
    /// in the summary field every fifth block. The second is that Markdown is
    /// what the design draws anyway: an `##` heading, one paragraph, an
    /// optional list, one emphasised term.
    ///
    /// What the model is *not* free to write is the rest of Markdown. Headings
    /// are `##` and nothing else, and there are no tables, code fences, images
    /// or links — see `NoteMarkdown`, which enforces that after decoding rather
    /// than trusting the prompt to have been read.
    var markdown: String

    var start: TimeInterval
    var end: TimeInterval

    var state: NoteBlockState

    var id: Int { number }

    /// The card's heading, which is also its row in the chapter rail.
    /// `nil` when the model wrote a card without one.
    var heading: String? { NoteMarkdown.heading(of: markdown) }

    init(
        number: Int,
        markdown: String,
        start: TimeInterval,
        end: TimeInterval,
        state: NoteBlockState = .written
    ) {
        self.number = number
        self.markdown = markdown
        self.start = start
        self.end = end
        self.state = state
    }
}

// MARK: - Chapters

/// One row in the chapter rail of the recording detail.
///
/// Derived from the note blocks at read time, never stored and never asked of
/// the model. The heading and the minute are both already known — the heading
/// because the block's Markdown carries it, the minute because the block knows
/// when it started — and a model asked for timestamps invents them.
nonisolated struct NoteChapter: Identifiable, Hashable, Sendable, Codable {

    /// The block this row brings into view.
    let blockNumber: Int

    var title: String
    var time: TimeInterval

    /// Drawn as the amber dot on the right of the row.
    var hasMarker: Bool

    var id: Int { blockNumber }
}

// MARK: - Final notes

/// The finished notes for one recording.
nonisolated struct RecordingNotes: Hashable, Sendable, Codable {

    /// What the meta strip labels "Topic · detected" and what the library table
    /// shows in its `Thema` column.
    ///
    /// **Nullable, and stays nullable all the way down.** A recording that was
    /// made but never summarised has no topic, and the interface draws its date
    /// and time in that column instead. A placeholder string would sort, search
    /// and read as if it were a real topic.
    var topic: String?

    /// The written-out notes, as Markdown. `##` headings, paragraphs, lists.
    var markdown: String

    /// The cards written while the recording ran, in order.
    ///
    /// Kept alongside the finished notes rather than replaced by them, because
    /// the chapter rail is read out of these: they are the only thing that
    /// knows which minute a heading belongs to.
    var blocks: [NoteBlock]

    /// Everything the user marked, in time order.
    var markers: [RecordingMarker]

    /// The chapter rail. Derived, so it costs nothing to be wrong about it.
    var chapters: [NoteChapter] {
        NoteChapters.entries(from: blocks, markers: markers)
    }

    init(
        topic: String?,
        markdown: String,
        blocks: [NoteBlock] = [],
        markers: [RecordingMarker] = []
    ) {
        self.topic = topic
        self.markdown = markdown
        self.blocks = blocks
        self.markers = markers
    }
}
