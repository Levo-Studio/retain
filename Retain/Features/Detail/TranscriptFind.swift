import Foundation

/// The find bar over the transcript: what matches, how many there are, and
/// which one is current.
///
/// A value rather than a piece of view state, because everything the bar draws
/// — the `3 of 11`, which line the pane scrolls to, which ranges are painted —
/// is a function of the lines and the query, and the only thing that is not is
/// the step through the matches.
nonisolated struct TranscriptFind: Equatable, Sendable {

    /// One match, as an offset into one line.
    ///
    /// Character offsets rather than `String.Index` so a match can be written
    /// down in a test, compared, and carried across a re-fetch of the lines
    /// without holding on to the string it was found in.
    nonisolated struct Match: Hashable, Sendable {
        let lineIndex: Int
        let range: Range<Int>
    }

    private(set) var query: String
    private(set) var matches: [Match]

    /// Index into `matches`. `nil` only when there are none — a query that
    /// matches always starts on its first hit, which is what makes typing into
    /// the field jump straight to something.
    private(set) var current: Int?

    // MARK: - Finding

    init(lines: [TranscriptLine] = [], query: String = "") {
        self.query = query
        matches = Self.matches(in: lines, query: query)
        current = matches.isEmpty ? nil : 0
    }

    /// Case- and diacritic-insensitive, because the transcript is German and
    /// somebody looking for "Bélády" will type "belady". `range(of:options:)`
    /// does the folding itself and reports the range in the original string, so
    /// the offsets stay offsets into the text as it is drawn.
    static func matches(in lines: [TranscriptLine], query: String) -> [Match] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var found: [Match] = []
        for (index, line) in lines.enumerated() {
            let text = line.text
            var searchFrom = text.startIndex

            while searchFrom < text.endIndex,
                  let hit = text.range(
                      of: needle,
                      options: [.caseInsensitive, .diacriticInsensitive],
                      range: searchFrom..<text.endIndex
                  ) {
                found.append(
                    Match(
                        lineIndex: index,
                        range: text.distance(from: text.startIndex, to: hit.lowerBound)
                            ..< text.distance(from: text.startIndex, to: hit.upperBound)
                    )
                )

                // A pattern that folds to nothing would otherwise stand still
                // here forever; stepping one character on is the only ending
                // that does not depend on the match having width.
                searchFrom = hit.upperBound > hit.lowerBound
                    ? hit.upperBound
                    : text.index(after: hit.lowerBound)
            }
        }
        return found
    }

    // MARK: - Stepping

    var count: Int { matches.count }

    /// The left half of "3 of 11" — one-based, and `nil` when there is nothing
    /// to count.
    var currentOrdinal: Int? {
        guard let current, !matches.isEmpty else { return nil }
        return current + 1
    }

    var currentMatch: Match? {
        guard let current, matches.indices.contains(current) else { return nil }
        return matches[current]
    }

    /// Wraps. The find bar has two arrows and no end: past the last match is
    /// the first one, which is what every find bar on this platform does and
    /// what stops the buttons from going dead at the ends of a long transcript.
    mutating func moveToNext() {
        guard !matches.isEmpty else { return }
        current = ((current ?? -1) + 1) % matches.count
    }

    mutating func moveToPrevious() {
        guard !matches.isEmpty else { return }
        current = ((current ?? 0) - 1 + matches.count) % matches.count
    }

    /// Every match inside one line, for painting them in place.
    func ranges(inLineAt index: Int) -> [Range<Int>] {
        matches.filter { $0.lineIndex == index }.map(\.range)
    }
}
