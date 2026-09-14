import Foundation
import GRDB

// The storage side of the model types.
//
// The types themselves live in `Models/` and know nothing about GRDB, which is
// what keeps the database out of the pipeline and out of the views. Everything
// that makes them rows is in this file.

// MARK: - Column values

/// Stored as the index the design offers it at, so a refreshed palette changes
/// no row.
nonisolated extension CourseColor: DatabaseValueConvertible {}

/// Stored as its name: `state = 'done'` reads in the sqlite shell, and a new
/// case is a new string rather than a renumbering of the old ones.
nonisolated extension RecordingState: DatabaseValueConvertible {}

/// Likewise `kind = 'semester'`.
nonisolated extension TermKind: DatabaseValueConvertible {}

/// `SpeakerRole` has no raw value — the pipeline has no use for one — so the
/// column mapping is written out here rather than bolted onto the model.
nonisolated extension SpeakerRole: DatabaseValueConvertible {

    var databaseValue: DatabaseValue {
        switch self {
        case .lecturer: "lecturer".databaseValue
        case .audience: "audience".databaseValue
        case .unknown: "unknown".databaseValue
        }
    }

    static func fromDatabaseValue(_ dbValue: DatabaseValue) -> SpeakerRole? {
        switch String.fromDatabaseValue(dbValue) {
        case "lecturer": .lecturer
        case "audience": .audience
        case "unknown": .unknown
        default: nil
        }
    }
}

// MARK: - Term

nonisolated extension Term: FetchableRecord, MutablePersistableRecord {

    static var databaseTableName: String { "term" }

    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let kind = Column("kind")
        static let startsOn = Column("startsOn")
        static let endsOn = Column("endsOn")
        static let isCurrent = Column("isCurrent")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Course

nonisolated extension Course: FetchableRecord, MutablePersistableRecord {

    static var databaseTableName: String { "course" }

    enum Columns {
        static let id = Column("id")
        static let termID = Column("termID")
        static let name = Column("name")
        static let color = Column("color")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Recording

nonisolated extension Recording: FetchableRecord, MutablePersistableRecord {

    static var databaseTableName: String { "recording" }

    enum Columns {
        static let id = Column("id")
        static let courseID = Column("courseID")
        static let startedAt = Column("startedAt")
        static let duration = Column("duration")
        static let state = Column("state")
        static let topic = Column("topic")
        static let filename = Column("filename")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Annotation

nonisolated extension Annotation: FetchableRecord, MutablePersistableRecord {

    static var databaseTableName: String { "annotation" }

    enum Columns {
        static let id = Column("id")
        static let recordingID = Column("recordingID")
        static let time = Column("time")
        static let note = Column("note")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Highlight

nonisolated extension Highlight: FetchableRecord, MutablePersistableRecord {

    static var databaseTableName: String { "highlight" }

    enum Columns {
        static let id = Column("id")
        static let recordingID = Column("recordingID")
        static let noteBlockID = Column("noteBlockID")
        static let startOffset = Column("startOffset")
        static let endOffset = Column("endOffset")
        static let text = Column("text")
        static let createdAt = Column("createdAt")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Transcript line

/// One `TranscriptLine` as it is stored.
///
/// A separate type from the model, because the two carry different things: a
/// stored line knows which recording it belongs to and has a row id, and a
/// `TranscriptLine` in the pipeline knows neither and must not, or the pipeline
/// would be writing rows.
///
/// `uuid` is the model's own `id`, kept across a save so that reloading a
/// transcript does not hand the view a completely new set of identities and
/// make it rebuild every row.
nonisolated struct TranscriptLineRecord: Hashable, Sendable, Codable {

    var id: Int64?
    var recordingID: Int64
    var uuid: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var speaker: SpeakerRole
    var isProvisional: Bool

    init(recordingID: Int64, line: TranscriptLine, id: Int64? = nil) {
        self.id = id
        self.recordingID = recordingID
        self.uuid = line.id
        self.startTime = line.start
        self.endTime = line.end
        self.text = line.text
        self.speaker = line.speaker
        self.isProvisional = line.isProvisional
    }

    var line: TranscriptLine {
        TranscriptLine(
            id: uuid,
            start: startTime,
            end: endTime,
            text: text,
            speaker: speaker,
            isProvisional: isProvisional
        )
    }
}

nonisolated extension TranscriptLineRecord: FetchableRecord, MutablePersistableRecord {

    static var databaseTableName: String { "transcriptLine" }

    enum Columns {
        static let id = Column("id")
        static let recordingID = Column("recordingID")
        static let uuid = Column("uuid")
        static let startTime = Column("startTime")
        static let endTime = Column("endTime")
        static let text = Column("text")
        static let speaker = Column("speaker")
        static let isProvisional = Column("isProvisional")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Note block

/// One written-out note block as it is stored — **the seam for the
/// summarisation layer**.
///
/// The content is the Markdown the model wrote: a heading, a paragraph,
/// bullets, an emphasised term. It is stored as it was written and not split
/// into parts, because the chapters rail is read back out of the headings and a
/// stored copy of a heading is a second place for it to be wrong.
///
/// Phase 4 owns how a block is produced and what the pipeline calls it. This
/// type is the shape it lands in: Markdown, its place in the reading order, and
/// the point in the recording it belongs to.
nonisolated struct StoredNoteBlock: Identifiable, Hashable, Sendable, Codable {

    var id: Int64?
    var recordingID: Int64

    /// Reading order, which is not always time order: a reduce over the block
    /// summaries can merge two stretches of the lecture into one note.
    var position: Int

    /// Where the block starts in the recording, on the same timeline as
    /// `TranscriptLine.start`. The chapters rail draws this and seeks to it.
    var startTime: TimeInterval

    /// Where it ends. Kept so a moment in the audio can be answered with the
    /// note covering it — playing the recording back and following along needs
    /// that direction, and `startTime` alone only answers the other one.
    var endTime: TimeInterval

    var markdown: String

    init(
        id: Int64? = nil,
        recordingID: Int64,
        position: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        markdown: String
    ) {
        self.id = id
        self.recordingID = recordingID
        self.position = position
        self.startTime = startTime
        self.endTime = endTime
        self.markdown = markdown
    }
}

nonisolated extension StoredNoteBlock: FetchableRecord, MutablePersistableRecord {

    static var databaseTableName: String { "noteBlock" }

    enum Columns {
        static let id = Column("id")
        static let recordingID = Column("recordingID")
        static let position = Column("position")
        static let startTime = Column("startTime")
        static let endTime = Column("endTime")
        static let markdown = Column("markdown")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
