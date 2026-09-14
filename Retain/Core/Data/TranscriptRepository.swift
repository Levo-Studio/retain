import Foundation
import GRDB

/// The transcript of a recording and the annotations typed during it.
///
/// Reads hand back `TranscriptLine`, the same value the pipeline and the views
/// already speak, so nothing outside `Core/Data/` ever sees a row.
nonisolated struct TranscriptRepository: Sendable {

    private let database: RetainDatabase

    init(_ database: RetainDatabase) {
        self.database = database
    }

    // MARK: - Lines

    /// Every line of a recording in time order — the order it is read and
    /// seeked in.
    func lines(for recordingID: Int64) async throws -> [TranscriptLine] {
        try await database.writer.read { db in
            try TranscriptLineRecord
                .filter(TranscriptLineRecord.Columns.recordingID == recordingID)
                .order(TranscriptLineRecord.Columns.startTime, TranscriptLineRecord.Columns.id)
                .fetchAll(db)
                .map(\.line)
        }
    }

    /// Appends one finished line of the live pass.
    ///
    /// Called once per `speechEnd` while the lecture runs, which is why it is a
    /// single insert and not a batch: the line is on screen already and the
    /// write is what makes it survive a crash mid-lecture.
    @discardableResult
    func append(_ line: TranscriptLine, to recordingID: Int64) async throws -> TranscriptLine {
        try await database.writer.write { db in
            var record = TranscriptLineRecord(recordingID: recordingID, line: line)
            try record.insert(db)
            return record.line
        }
    }

    /// Replaces the whole transcript of a recording.
    ///
    /// This is what the batch pass does when it lands: the live lines were
    /// feedback at around 10 % word error, the batch lines are the record at
    /// around 5.9 %, and merging the two would leave a transcript that is
    /// partly one and partly the other. One transaction, so a reader either
    /// sees the old transcript or the new one and never half of each.
    func replaceLines(_ lines: [TranscriptLine], for recordingID: Int64) async throws {
        try await database.writer.write { db in
            try TranscriptLineRecord
                .filter(TranscriptLineRecord.Columns.recordingID == recordingID)
                .deleteAll(db)

            for line in lines {
                var record = TranscriptLineRecord(recordingID: recordingID, line: line)
                try record.insert(db)
            }
        }
    }

    /// Corrects one line in place, found by the id it carries.
    ///
    /// The search index follows on its own: the update trigger on
    /// `transcriptLine` removes the old terms and indexes the new ones.
    func update(_ line: TranscriptLine, in recordingID: Int64) async throws {
        try await database.writer.write { db in
            _ = try TranscriptLineRecord
                .filter(TranscriptLineRecord.Columns.recordingID == recordingID)
                .filter(TranscriptLineRecord.Columns.uuid == line.id)
                .updateAll(db, [
                    TranscriptLineRecord.Columns.startTime.set(to: line.start),
                    TranscriptLineRecord.Columns.endTime.set(to: line.end),
                    TranscriptLineRecord.Columns.text.set(to: line.text),
                    TranscriptLineRecord.Columns.speaker.set(to: line.speaker),
                    TranscriptLineRecord.Columns.isProvisional.set(to: line.isProvisional),
                ])
        }
    }

    // MARK: - Annotations

    /// In time order, which is the order the rail lists them in.
    func annotations(for recordingID: Int64) async throws -> [Annotation] {
        try await database.writer.read { db in
            try Annotation
                .filter(Annotation.Columns.recordingID == recordingID)
                .order(Annotation.Columns.time)
                .fetchAll(db)
        }
    }

    @discardableResult
    func annotate(
        at time: TimeInterval,
        note: String? = nil,
        in recordingID: Int64
    ) async throws -> Annotation {
        try await database.writer.write { db in
            var annotation = Annotation(recordingID: recordingID, time: time, note: note)
            try annotation.insert(db)
            return annotation
        }
    }
}
