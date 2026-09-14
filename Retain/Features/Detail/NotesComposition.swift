import Foundation

// MARK: - What the notes pane draws, in order

/// One thing in the notes column.
///
/// Board 03 draws two shapes: the model's cards, and an annotation the user
/// typed during the lecture sitting between them behind a blue rule. They are
/// one list rather than two columns, so they are one list here.
nonisolated enum NoteItem: Hashable, Sendable, Identifiable {

    case block(NoteBlock)
    case annotation(Annotation)

    var id: String {
        switch self {
        case let .block(block): "block-\(block.number)"
        case let .annotation(annotation): "annotation-\(annotation.id ?? 0)-\(annotation.time)"
        }
    }
}

// MARK: -

nonisolated enum NotesComposition {

    /// Lays the cards and the annotations out on one timeline.
    ///
    /// An annotation belongs after the card whose stretch of the lecture it
    /// falls in — that is where board 03 puts the one at 00:52:10, under the
    /// block that starts at 00:49 — because that is the passage it is a remark
    /// about. Anything falling in the gap between two cards goes before the
    /// next one rather than after the previous, so a remark typed at the moment
    /// a new topic started introduces it.
    ///
    /// An annotation outside every block — typed in the first seconds, or after
    /// the last card closed — still appears, because the user wrote it and the
    /// notes are the only place it is ever shown.
    ///
    /// The one thing that does not appear is a **bare marker**: `⌘⇧M` pressed
    /// without anything typed after it. It is a real thing — it counts in the
    /// meta strip and it puts the amber dot on its chapter — but it has no text,
    /// and board 03 draws an annotation as a label above a sentence. A blue
    /// rule with nothing beside it is not that.
    static func items(blocks: [NoteBlock], annotations: [Annotation]) -> [NoteItem] {
        var pending = annotations
            .filter { !($0.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.time < $1.time }
        var items: [NoteItem] = []

        func drain(while include: (Annotation) -> Bool) {
            while let first = pending.first, include(first) {
                items.append(.annotation(first))
                pending.removeFirst()
            }
        }

        for block in blocks.sorted(by: { $0.number < $1.number }) {
            drain { $0.time < block.start }
            items.append(.block(block))
            drain { $0.time <= block.end }
        }

        items.append(contentsOf: pending.map(NoteItem.annotation))
        return items
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
