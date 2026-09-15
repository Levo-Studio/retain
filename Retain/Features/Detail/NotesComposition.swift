import Foundation

// MARK: - What the notes pane draws, in order

/// One thing in the notes column.
///
/// One case, and it used to be two. Board 03 draws an annotation the student
/// typed sitting between the cards behind a blue rule, and that is how it
/// worked until the owner asked for the opposite: a remark is not a thing to
/// park at the end of the notes in the words it was typed in, it is something
/// the model has to have understood. It now goes to the model instead — see
/// `NoteReduction.reduceSystemPrompt`, which has to work its meaning into the
/// section covering its timestamp and is forbidden from quoting it.
///
/// The enum stays an enum rather than collapsing to `NoteBlock`, because the
/// column is a list of things that are drawn and there is no reason to believe
/// it will only ever hold one kind.
nonisolated enum NoteItem: Hashable, Sendable, Identifiable {

    case block(NoteBlock)

    var id: String {
        switch self {
        case let .block(block): Self.id(ofBlock: block.number)
        }
    }

    /// What a chapter row and a chat citation scroll to. They know a block
    /// number and not the block, so the id is built in one place rather than
    /// spelled the same way twice.
    static func id(ofBlock number: Int) -> String { "block-\(number)" }
}

// MARK: -

nonisolated enum NotesComposition {

    /// The cards, in order.
    ///
    /// The annotations are taken and not drawn. They are the student's own
    /// remarks, and the owner's instruction is that they reach the notes
    /// through the model rather than beside it: their meaning belongs inside
    /// the section they were typed during, in the notes' own voice, not parked
    /// at the bottom of the column in the shorthand they were typed in.
    /// `NoteReduction.reducePrompt` is where they go, and the rule that none of
    /// them may be dropped is in the system prompt beside it.
    ///
    /// **This is a departure from board 03**, which draws the blue-ruled card
    /// between the blocks. It is a deliberate one, asked for by the owner, and
    /// it is not licence to move anything else the export draws.
    ///
    /// Nothing about a remark is lost by not drawing it: it is still stored,
    /// still counted in the meta strip, and still puts the amber dot on the
    /// chapter it falls in — see `NoteChapters.entries(from:markers:)`.
    ///
    /// - Parameter annotations: unused, and kept in the signature because the
    ///   caller has them and the question "where do these go" is answered here
    ///   rather than at the call site.
    static func items(blocks: [NoteBlock], annotations: [Annotation]) -> [NoteItem] {
        blocks.sorted { $0.number < $1.number }.map(NoteItem.block)
    }
}

// MARK: - Which block the reader is looking at

/// The chapter rail follows the reader down the page.
///
/// It used to move only when something moved it — a chapter clicked, a chat
/// citation followed — so scrolling through an hour of notes left the accent
/// rule on whichever row was last pressed, which is a rail describing where the
/// reader has been rather than where they are.
///
/// A pure function over where the blocks sit, so the rule that decides it is
/// testable without a scroll view.
nonisolated enum NotesScroll {

    /// - Parameters:
    ///   - readingLine: how far below the top of the visible area counts as
    ///     being read. Not the very top edge: a block whose heading has only
    ///     just appeared at the bottom is not the block anybody is reading, and
    ///     a rule that jumps on the first pixel jumps back on the next.
    ///   - tops: every block's number against the y of its top edge, in the
    ///     scroll view's own space — zero at the top of the visible area and
    ///     negative once it has scrolled past.
    /// - Returns: the block that has most recently crossed the line, or the
    ///   first one before any has. Never `nil` for a non-empty page, because
    ///   board 03 draws exactly one row picked out and never none.
    static func block(at readingLine: CGFloat, tops: [Int: CGFloat]) -> Int? {
        let begun = tops.filter { $0.value <= readingLine }
        if let current = begun.max(by: { $0.value < $1.value }) { return current.key }
        return tops.min(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Anchoring a highlight to the text as it is drawn

/// Turns stored highlights into the ranges `RetainMarkdownView` paints.
///
/// The two sides measure different things, which is the whole reason this
/// exists. A `Highlight` is stored as **UTF-8 byte offsets into the block's
/// Markdown** — the unit SQLite and the store agree on. `RetainMarkdownView`
/// wants **character offsets into the rendered plain text**, which is the
/// Markdown with `##`, `- ` and `**` taken out of it. There is no arithmetic
/// between the two.
///
/// So the anchor is the text itself. Every highlight carries a copy of what was
/// marked, kept precisely for the case where the notes have been written again
/// since, and finding that copy in the rendered text is both exact when the
/// notes have not changed and the best available answer when they have.
nonisolated enum NoteHighlightAnchoring {

    /// - Returns: ranges into `RetainMarkdown.plainText(of:)` of `markdown`,
    ///   in order and without overlaps. A highlight whose text is no longer in
    ///   the block yields nothing: painting the wrong sentence is worse than
    ///   painting none, and the highlight itself is not lost — it is still in
    ///   the store with its text in it.
    static func ranges(of highlights: [Highlight], in markdown: String) -> [Range<Int>] {
        let plain = RetainMarkdown.plainText(of: RetainMarkdown.elements(of: markdown))
        guard !plain.isEmpty else { return [] }

        let markdownBytes = markdown.utf8.count
        let found = highlights.compactMap { highlight -> Range<Int>? in
            range(of: highlight.text, in: plain, near: highlight.startOffset, of: markdownBytes)
        }
        return merged(found.sorted { $0.lowerBound < $1.lowerBound })
    }

    /// The occurrence of `needle` that sits where the stored offset says it
    /// should.
    ///
    /// A word marked twice in one card is the ordinary case — a definition and
    /// then its use — so "the first occurrence" would move the mark. Comparing
    /// how far through each text the two positions are is not exact, and does
    /// not need to be: it only has to separate occurrences from each other, and
    /// two occurrences of the same phrase in one three-minute block are never
    /// close enough together for it to pick the wrong one.
    static func range(
        of needle: String,
        in plain: String,
        near byteOffset: Int,
        of markdownBytes: Int
    ) -> Range<Int>? {
        guard !needle.isEmpty else { return nil }

        var occurrences: [Range<Int>] = []
        var searchFrom = plain.startIndex
        while searchFrom < plain.endIndex,
              let hit = plain.range(of: needle, range: searchFrom..<plain.endIndex) {
            occurrences.append(
                plain.distance(from: plain.startIndex, to: hit.lowerBound)
                    ..< plain.distance(from: plain.startIndex, to: hit.upperBound)
            )
            searchFrom = hit.upperBound > hit.lowerBound
                ? hit.upperBound
                : plain.index(after: hit.lowerBound)
        }

        guard occurrences.count > 1 else { return occurrences.first }

        let wanted = markdownBytes > 0 ? Double(byteOffset) / Double(markdownBytes) : 0
        let length = Double(plain.count)
        return occurrences.min { left, right in
            abs(Double(left.lowerBound) / length - wanted)
                < abs(Double(right.lowerBound) / length - wanted)
        }
    }

    /// Two marks that touch or overlap are one mark. Painting them separately
    /// would draw the rounded ends of both in the middle of a sentence.
    static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
