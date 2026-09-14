import Foundation
import GRDB

/// One match, with everything needed to draw it and to jump to it.
///
/// `recordingID` and `time` together are the seek target: open that recording
/// and play from that second. Everything else is what the row is labelled with.
nonisolated struct SearchHit: Identifiable, Hashable, Sendable {

    nonisolated enum Source: Hashable, Sendable {
        case transcript
        case note
        case annotation
    }

    let id: String
    let source: Source

    let recordingID: Int64
    /// When the recording happened, date and time of day. It is what a
    /// recording is identified by, so it is what the row is labelled with.
    let recordingDate: Date
    /// `nil` for a recording the model never got a topic out of; the row then
    /// draws the date alone.
    let recordingTopic: String?

    let courseID: Int64
    let courseName: String

    /// Seconds from the start of the recording.
    let time: TimeInterval

    /// The text the match is in: the transcript line, the note block's
    /// Markdown, or what the user typed into the annotation.
    let text: String
}

// MARK: -

/// Full-text search across one term.
///
/// The term is not an optional filter that happens to be applied — it is the
/// scope. Board 05's field says so: "Search every recording in this term". A
/// hit from a course the user is not taking this half-year is noise.
nonisolated struct SearchRepository: Sendable {

    private let database: RetainDatabase

    init(_ database: RetainDatabase) {
        self.database = database
    }

    /// Everything in `termID` that matches — transcript lines, notes and
    /// annotations together, newest recording first.
    ///
    /// The pattern comes from `FTS5Pattern(matchingAllPrefixesIn:)`, which is
    /// the one safe way to turn what somebody typed into a search field into an
    /// FTS5 expression: it drops the syntax characters — quotes, colons,
    /// `NOT`, `*`, the parentheses — instead of letting them reach the FTS5
    /// parser, where "Kap. 3:" is a syntax error rather than a search. Prefixes
    /// and not whole tokens because the field is read while it is being typed,
    /// so "work" has to find "working" before the user has finished the word.
    /// A query with nothing searchable in it matches nothing, rather than
    /// everything.
    func search(_ query: String, in termID: Int64, limit: Int = 50) async throws -> [SearchHit] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }

        return try await database.writer.read { db in
            let hits = try transcriptHits(db, pattern: pattern, termID: termID, limit: limit)
                + noteHits(db, pattern: pattern, termID: termID, limit: limit)
                + annotationHits(db, pattern: pattern, termID: termID, limit: limit)

            // Ranked by date, not by bm25. The control the design draws beside
            // the field says "by date", and a relevance score from three
            // separate FTS5 tables is not comparable between them anyway —
            // each is scored against its own corpus.
            return hits
                .sorted { left, right in
                    if left.recordingDate != right.recordingDate {
                        return left.recordingDate > right.recordingDate
                    }
                    return left.time < right.time
                }
                .prefix(limit)
                .map { $0 }
        }
    }

    // MARK: - The three indexes

    /// Everything the three queries have in common: the join that scopes a
    /// match to a term, and the columns a hit is labelled with.
    ///
    /// The FTS table carries no term, so every match is walked back to its
    /// recording and its course to see which term it belongs to. That is also
    /// why the index is external-content — the row it points at is the real
    /// one, so the join is against live data and not a copy.
    private func sql(searchTable: String, contentTable: String, text: String, time: String) -> String {
        """
        SELECT \(contentTable).id AS hitID,
               \(contentTable).recordingID AS recordingID,
               \(time) AS time,
               \(text) AS text,
               recording.date AS recordingDate,
               recording.topic AS recordingTopic,
               course.id AS courseID,
               course.name AS courseName
        FROM \(searchTable)
        JOIN \(contentTable) ON \(contentTable).id = \(searchTable).rowid
        JOIN recording ON recording.id = \(contentTable).recordingID
        JOIN course ON course.id = recording.courseID
        WHERE \(searchTable) MATCH ? AND course.termID = ?
        ORDER BY recording.date DESC, time
        LIMIT ?
        """
    }

    private func hits(
        _ db: Database,
        sql: String,
        pattern: FTS5Pattern,
        termID: Int64,
        limit: Int,
        source: SearchHit.Source,
        prefix: String
    ) throws -> [SearchHit] {
        try Row
            .fetchAll(db, sql: sql, arguments: [pattern, termID, limit])
            .map { row in
                SearchHit(
                    id: "\(prefix)-\(row["hitID"] as Int64)",
                    source: source,
                    recordingID: row["recordingID"],
                    recordingDate: row["recordingDate"],
                    recordingTopic: row["recordingTopic"],
                    courseID: row["courseID"],
                    courseName: row["courseName"],
                    time: row["time"],
                    text: row["text"]
                )
            }
    }

    private func transcriptHits(
        _ db: Database,
        pattern: FTS5Pattern,
        termID: Int64,
        limit: Int
    ) throws -> [SearchHit] {
        try hits(
            db,
            sql: sql(
                searchTable: "transcriptLineSearch",
                contentTable: "transcriptLine",
                text: "transcriptLine.text",
                time: "transcriptLine.startTime"
            ),
            pattern: pattern,
            termID: termID,
            limit: limit,
            source: .transcript,
            prefix: "transcript"
        )
    }

    private func noteHits(
        _ db: Database,
        pattern: FTS5Pattern,
        termID: Int64,
        limit: Int
    ) throws -> [SearchHit] {
        try hits(
            db,
            sql: sql(
                searchTable: "noteBlockSearch",
                contentTable: "noteBlock",
                text: "noteBlock.markdown",
                time: "noteBlock.startTime"
            ),
            pattern: pattern,
            termID: termID,
            limit: limit,
            source: .note,
            prefix: "note"
        )
    }

    /// The annotation text is the one thing in here the user wrote themselves,
    /// which makes it the most likely thing they will come back looking for.
    private func annotationHits(
        _ db: Database,
        pattern: FTS5Pattern,
        termID: Int64,
        limit: Int
    ) throws -> [SearchHit] {
        try hits(
            db,
            sql: sql(
                searchTable: "annotationSearch",
                contentTable: "annotation",
                // An annotation set without text indexes nothing and can never
                // match, so the coalesce only ever feeds the label.
                text: "COALESCE(annotation.note, '')",
                time: "annotation.time"
            ),
            pattern: pattern,
            termID: termID,
            limit: limit,
            source: .annotation,
            prefix: "annotation"
        )
    }
}
