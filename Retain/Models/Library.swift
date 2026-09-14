import Foundation

// MARK: - Term

/// What a term is a term of.
///
/// The user picks one per term rather than once for the app: somebody who
/// changes school, or changes country, keeps the half-years they already
/// recorded as half-years instead of having them silently re-labelled.
nonisolated enum TermKind: String, CaseIterable, Hashable, Sendable, Codable {
    case halfYear
    case semester
}

/// The stretch of time the library is filtered by.
///
/// It is the top-level filter: the pill in the library title bar picks one, the
/// sidebar then shows the courses in it and nothing else, and search covers it
/// and nothing else.
nonisolated struct Term: Identifiable, Hashable, Sendable, Codable {

    /// `nil` until the row has been written. The store fills it in on insert.
    var id: Int64?

    /// Free text the user types — "Third year, winter". There is no format and
    /// no derivation from the period; the dialog offers a plain field.
    var title: String

    var kind: TermKind

    /// The period, at month granularity: the dialog offers "Oct 2025" and
    /// "Mar 2026", never a day. Stored as an instant inside that month so two
    /// terms sort against each other without a second column.
    ///
    /// **Both endpoints are optional, and nothing computes with either.** The
    /// period is the caption under the term's name in board 05's sidebar and
    /// nowhere else: a recording carries the term it was made in, so no filter,
    /// no grouping and no lookup ever asks a date which term it falls in. A
    /// term with one endpoint, or with none, works completely — see
    /// `TermPeriod` for how each of those reads.
    var startsOn: Date?
    var endsOn: Date?

    /// The term the picker opens on. At most one row carries it, which
    /// `LibraryRepository.makeCurrent(_:)` is the only way to set.
    var isCurrent: Bool

    init(
        id: Int64? = nil,
        title: String,
        kind: TermKind = .halfYear,
        startsOn: Date? = nil,
        endsOn: Date? = nil,
        isCurrent: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.isCurrent = isCurrent
    }
}

// MARK: - Course

/// The four colours the new-course dialog offers, in the order it offers them.
///
/// Stored as the index, never as a hex string: the values live in
/// `docs/design/README.md` under "Accents" and belong in the design layer, so a
/// colour written into the database would go stale the moment the export is
/// refreshed.
nonisolated enum CourseColor: Int, CaseIterable, Hashable, Sendable, Codable {
    case accent = 0
    case blue = 1
    case amber = 2
    case purple = 3
}

/// One subject, once — however many terms it runs in.
///
/// The same school subject runs in the winter half-year and in the summer one,
/// and it is **the same course**: renaming it renames it in both, and its
/// colour is its colour everywhere. Which terms it runs in is the `courseTerm`
/// table, and what was recorded in each of them is the recording's own term, so
/// board 05 still shows only the term being looked at — the filter moved off
/// the course and onto the recording, where it can be exact.
nonisolated struct Course: Identifiable, Hashable, Sendable, Codable {

    var id: Int64?
    var name: String
    var color: CourseColor

    init(id: Int64? = nil, name: String, color: CourseColor) {
        self.id = id
        self.name = name
        self.color = color
    }
}

// MARK: - Which terms a course runs in

/// One course being in one term.
///
/// The whole row is the pairing: a course keeps its name and its colour in one
/// place, and this says which terms it appears in. Adding a course to a second
/// term is one of these, not a second course — which is what makes renaming
/// "Computer science" rename it in the winter half-year and the summer one at
/// the same time.
nonisolated struct CourseTerm: Identifiable, Hashable, Sendable, Codable {

    var id: Int64?
    var courseID: Int64
    var termID: Int64

    init(id: Int64? = nil, courseID: Int64, termID: Int64) {
        self.id = id
        self.courseID = courseID
        self.termID = termID
    }
}

// MARK: - Recording

/// Where a recording has got to.
///
/// The Status column draws the first and the last. The two in between are what
/// the pass after the microphone stops actually goes through — the batch
/// re-transcription, then the summarisation — and the popover draws the second
/// of them as "Summarizing". A recording stuck in either is one whose model
/// work did not finish, which the interface has to be able to tell from a
/// finished one.
nonisolated enum RecordingState: String, CaseIterable, Hashable, Sendable, Codable {
    case recording
    case transcribing
    case summarizing
    case done
}

/// One recording, from the first second of audio to the finished notes.
///
/// **There is no lesson and no lesson number.** A recording is identified by
/// when it happened — the date *and* the time of day — and described by a topic
/// the language model reads out of the transcript. Nobody types either. Two
/// recordings on the same afternoon are ordinary, so nothing here may reduce a
/// recording to the day it fell on.
nonisolated struct Recording: Identifiable, Hashable, Sendable, Codable {

    var id: Int64?
    var courseID: Int64

    /// The term the recording was made in — whichever one was current when the
    /// microphone opened.
    ///
    /// **It is carried, not derived.** A term's period is optional, so the date
    /// cannot answer which term a recording falls in; and a course runs in
    /// several terms, so the course cannot either. Carrying it also means
    /// editing a term's period afterwards moves no recordings, which a derived
    /// answer would do silently.
    var termID: Int64

    /// When the recording started, to the second.
    ///
    /// Not a day, which is why it is not called one: the interface draws the
    /// time of day beside the date, and two recordings can fall on the same
    /// afternoon.
    var startedAt: Date

    /// Seconds of recorded audio. Zero while the first minute is still running.
    var duration: TimeInterval

    var state: RecordingState

    /// `nil` until the model has read the transcript, and `nil` forever for a
    /// recording whose summarisation never ran. Not defaulted to a placeholder
    /// — the interface draws the date and time instead, which is honest.
    var topic: String?

    /// The audio's file name, never its path.
    ///
    /// The folder is `RecordingStore.directory`, which is derived at read time.
    /// Storing the full path would put the user's home directory into the
    /// database and into everything derived from it, and would break the moment
    /// the folder moves.
    var filename: String?

    init(
        id: Int64? = nil,
        courseID: Int64,
        termID: Int64,
        startedAt: Date,
        duration: TimeInterval = 0,
        state: RecordingState = .recording,
        topic: String? = nil,
        filename: String? = nil
    ) {
        self.id = id
        self.courseID = courseID
        self.termID = termID
        self.startedAt = startedAt
        self.duration = duration
        self.state = state
        self.topic = topic
        self.filename = filename
    }
}

// MARK: - Annotation

/// What `⌘⇧M` produces during the lecture: a line the user types, anchored to
/// the second they typed it at.
///
/// It goes to the model with the block it falls in and comes back out in the
/// notes as "You · 00:52:10". `note` is the text; a marker set without any is
/// still a point worth jumping to, so it stays optional.
nonisolated struct Annotation: Identifiable, Hashable, Sendable, Codable {

    var id: Int64?
    var recordingID: Int64

    /// Seconds from the start of the recording, on the same timeline as
    /// `TranscriptLine.start`, so an annotation is a seek target like any line.
    var time: TimeInterval

    var note: String?

    init(id: Int64? = nil, recordingID: Int64, time: TimeInterval, note: String? = nil) {
        self.id = id
        self.recordingID = recordingID
        self.time = time
        self.note = note
    }
}

// MARK: - Highlight

/// A passage of the finished notes the user has marked, during the lecture or
/// long after it.
///
/// Not a point in the audio: a highlight anchors to a note block and a range
/// inside that block's Markdown, because what is being marked is a sentence
/// somebody wants to find again, not a second of sound.
///
/// **The offsets are UTF-8 byte offsets into `StoredNoteBlock.markdown`, half
/// open.** Bytes rather than "characters" because Swift has three defensible
/// answers to what a character is and SQLite stores the column as UTF-8, so
/// this is the one unit that means the same thing on both sides.
nonisolated struct Highlight: Identifiable, Hashable, Sendable, Codable {

    var id: Int64?

    /// Kept alongside `noteBlockID`, which it could be derived from, because
    /// "every highlight in this recording" is a question the interface asks
    /// far more often than "every highlight in this block".
    var recordingID: Int64
    var noteBlockID: Int64

    var startOffset: Int
    var endOffset: Int

    /// What was marked, copied out of the block at the moment of marking.
    ///
    /// Redundant while the notes stand still, and the only thing left when they
    /// do not: a re-summarised block is new Markdown, and offsets into a text
    /// that no longer exists cannot say what they once covered. With the text
    /// beside them the passage can be searched for in the new notes and
    /// re-anchored, and if it is not there at all it can still be shown to the
    /// user as what they marked. What *should* happen to a highlight when the
    /// summary is written again is not settled here; this only keeps the
    /// question answerable.
    var text: String

    var createdAt: Date

    init(
        id: Int64? = nil,
        recordingID: Int64,
        noteBlockID: Int64,
        startOffset: Int,
        endOffset: Int,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.recordingID = recordingID
        self.noteBlockID = noteBlockID
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.text = text
        self.createdAt = createdAt
    }
}
