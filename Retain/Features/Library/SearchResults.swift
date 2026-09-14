import Foundation

/// Every hit in one recording, under one heading.
///
/// The repository returns a flat list of matches over three indexes, and a flat
/// list is the wrong shape to read: four lines from the same afternoon are one
/// answer — "it was in that lecture" — and reading them as four separate
/// results makes the person scan the same date four times.
nonisolated struct SearchResultGroup: Identifiable, Hashable, Sendable {

    let recordingID: Int64
    let startedAt: Date
    /// `nil` for a recording the model never got a topic out of; the heading
    /// then carries the date, exactly as the table's Topic column does.
    let topic: String?
    let courseName: String

    var hits: [SearchHit]

    var id: Int64 { recordingID }
}

// MARK: -

nonisolated enum SearchResults {

    /// Groups the hits by recording.
    ///
    /// **Newest recording first, and inside a recording earliest second
    /// first.** That is the order board 05's control names — "by date" — and
    /// it is the only order that is comparable: the three FTS5 indexes score
    /// against three different corpora, so a relevance ranking across them
    /// would be a ranking of nothing.
    static func groups(from hits: [SearchHit]) -> [SearchResultGroup] {
        var order: [Int64] = []
        var byRecording: [Int64: SearchResultGroup] = [:]

        for hit in hits {
            if byRecording[hit.recordingID] == nil {
                order.append(hit.recordingID)
                byRecording[hit.recordingID] = SearchResultGroup(
                    recordingID: hit.recordingID,
                    startedAt: hit.recordingStartedAt,
                    topic: hit.recordingTopic,
                    courseName: hit.courseName,
                    hits: []
                )
            }
            byRecording[hit.recordingID]?.hits.append(hit)
        }

        return order
            .compactMap { byRecording[$0] }
            .map { group in
                var group = group
                group.hits.sort { left, right in
                    left.time != right.time ? left.time < right.time : left.id < right.id
                }
                return group
            }
            .sorted { left, right in
                left.startedAt != right.startedAt
                    ? left.startedAt > right.startedAt
                    : left.recordingID > right.recordingID
            }
    }

    /// What a hit row says it came from.
    static func label(for source: SearchHit.Source) -> String {
        switch source {
        case .transcript: LibraryCopy.hitInTranscript
        case .note: LibraryCopy.hitInNotes
        case .annotation: LibraryCopy.hitInAnnotation
        }
    }

    /// A note block's Markdown is a heading, a paragraph and a list; a row in a
    /// list of results has one line. This takes the first line that has words
    /// in it, with the `##` and the `- ` off, so the row reads as a sentence
    /// rather than as source.
    static func snippet(of hit: SearchHit) -> String {
        guard hit.source == .note else {
            return hit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let elements = RetainMarkdown.elements(of: hit.text)
        let plain = RetainMarkdown.plainText(of: elements)
        return plain
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? hit.text
    }
}
