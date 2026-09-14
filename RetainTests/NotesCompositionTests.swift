import Foundation
import Testing

@testable import Retain

private func block(_ number: Int, _ heading: String, start: TimeInterval, end: TimeInterval) -> NoteBlock {
    NoteBlock(number: number, markdown: "## \(heading)\nAbsatz über \(heading).", start: start, end: end)
}

private func annotation(_ id: Int64, at time: TimeInterval, _ note: String) -> Annotation {
    Annotation(id: id, recordingID: 1, time: time, note: note)
}

// MARK: - The order things are drawn in

@Suite("Notes composition")
struct NotesCompositionTests {

    private let blocks = [
        block(1, "Wann eine Seite verdrängt werden darf", start: 240, end: 2940),
        block(2, "Working Set und Thrashing", start: 2940, end: 5520),
    ]

    @Test("An annotation sits under the card whose stretch it falls in")
    func annotationUnderItsBlock() {
        let items = NotesComposition.items(
            blocks: blocks,
            annotations: [annotation(1, at: 3130, "Übungsblatt 5, Aufgabe 3 rechnet genau diesen Fall durch.")]
        )

        #expect(items.count == 3)
        #expect(items[0] == .block(blocks[0]))
        #expect(items[1] == .block(blocks[1]))
        if case let .annotation(found) = items[2] {
            #expect(found.time == 3130)
        } else {
            Issue.record("the annotation should be the last item")
        }
    }

    @Test("Several annotations in one card keep their time order")
    func severalInOneBlock() {
        let items = NotesComposition.items(
            blocks: blocks,
            annotations: [annotation(2, at: 4000, "zweite"), annotation(1, at: 3130, "erste")]
        )

        let times = items.compactMap { item -> TimeInterval? in
            if case let .annotation(found) = item { return found.time }
            return nil
        }
        #expect(times == [3130, 4000])
    }

    /// A remark typed at the moment a new topic started introduces that topic;
    /// it does not belong under the one that just ended.
    @Test("An annotation in the gap between two cards introduces the next one")
    func inTheGap() {
        let spaced = [
            block(1, "Erstes", start: 0, end: 600),
            block(2, "Zweites", start: 1200, end: 1800),
        ]
        let items = NotesComposition.items(blocks: spaced, annotations: [annotation(1, at: 900, "dazwischen")])

        #expect(items[0] == .block(spaced[0]))
        if case .annotation = items[1] {} else { Issue.record("the annotation should come before the second card") }
        #expect(items[2] == .block(spaced[1]))
    }

    @Test("An annotation outside every card is still drawn")
    func outsideEveryBlock() {
        let items = NotesComposition.items(
            blocks: blocks,
            annotations: [annotation(1, at: 10, "ganz früh"), annotation(2, at: 9_000, "ganz spät")]
        )

        #expect(items.count == 4)
        if case .annotation = items.first {} else { Issue.record("the early one comes first") }
        if case .annotation = items.last {} else { Issue.record("the late one comes last") }
    }

    @Test("Cards with no annotations are just the cards, in order")
    func noAnnotations() {
        #expect(NotesComposition.items(blocks: blocks, annotations: []).count == 2)
    }

    /// `⌘⇧M` with nothing typed after it is a real marker — it counts in the
    /// meta strip and puts the amber dot on its chapter — but board 03 draws an
    /// annotation as a label above a sentence, and there is no sentence.
    @Test("A marker with nothing typed after it draws no annotation")
    func bareMarker() {
        let bare = Annotation(id: 1, recordingID: 1, time: 3130, note: nil)
        let blank = Annotation(id: 2, recordingID: 1, time: 3200, note: "   ")
        let real = Annotation(id: 3, recordingID: 1, time: 3300, note: "etwas")

        let items = NotesComposition.items(blocks: blocks, annotations: [bare, blank, real])

        #expect(items.count == 3)
        if case let .annotation(found) = items[2] {
            #expect(found.id == 3)
        } else {
            Issue.record("only the marker that was written on should be drawn")
        }
    }
}

// MARK: - Anchoring a highlight

@Suite("Highlight anchoring")
struct NoteHighlightAnchoringTests {

    private let markdown = """
        ## Working Set und Thrashing
        Das **Working Set** ist die Menge der Seiten, die ein Prozess anfasst.
        """

    private func highlight(_ text: String, at offset: Int) -> Highlight {
        Highlight(
            id: 1,
            recordingID: 1,
            noteBlockID: 1,
            startOffset: offset,
            endOffset: offset + text.utf8.count,
            text: text
        )
    }

    @Test("A marked phrase is found in the text as it is drawn, not as it is stored")
    func findsThePhrase() throws {
        let ranges = NoteHighlightAnchoring.ranges(
            of: [highlight("die Menge der Seiten", at: 0)],
            in: markdown
        )

        let plain = RetainMarkdown.plainText(of: RetainMarkdown.elements(of: markdown))
        let range = try #require(ranges.first)
        #expect(String(Array(plain)[range]) == "die Menge der Seiten")
    }

    /// The offsets are UTF-8 bytes into Markdown and the renderer wants
    /// characters of rendered text; the `##` and the `**` are exactly what
    /// makes the two disagree.
    @Test("The markers the renderer strips do not shift the anchor")
    func survivesTheMarkers() throws {
        let ranges = NoteHighlightAnchoring.ranges(of: [highlight("Working Set", at: 3)], in: markdown)
        let plain = Array(RetainMarkdown.plainText(of: RetainMarkdown.elements(of: markdown)))
        let range = try #require(ranges.first)

        #expect(String(plain[range]) == "Working Set")
    }

    @Test("A phrase that is no longer in the card is not painted somewhere else")
    func rewrittenNotes() {
        let ranges = NoteHighlightAnchoring.ranges(
            of: [highlight("Bélády-Anomalie", at: 0)],
            in: markdown
        )
        #expect(ranges.isEmpty)
    }

    @Test("A phrase that appears twice takes the occurrence the stored offset points at")
    func picksTheRightOccurrence() throws {
        let twice = """
            ## Clock
            Clock ist Second Chance als Ringpuffer. Second Chance sortiert dabei nicht um.
            """
        let plain = Array(RetainMarkdown.plainText(of: RetainMarkdown.elements(of: twice)))

        // The second "Second Chance" — its byte offset is well past the middle
        // of the Markdown.
        let offset = try #require(twice.range(of: "Second Chance", options: .backwards))
            .lowerBound.utf8Offset(in: twice)

        let ranges = NoteHighlightAnchoring.ranges(
            of: [
                Highlight(
                    id: 1,
                    recordingID: 1,
                    noteBlockID: 1,
                    startOffset: offset,
                    endOffset: offset + "Second Chance".utf8.count,
                    text: "Second Chance"
                )
            ],
            in: twice
        )

        let range = try #require(ranges.first)
        #expect(String(plain[range]) == "Second Chance")
        #expect(range.lowerBound > plain.count / 2)
    }

    @Test("Marks that touch are drawn as one, so no rounded end lands mid-sentence")
    func mergesOverlaps() {
        #expect(NoteHighlightAnchoring.merged([0..<10, 8..<20]) == [0..<20])
        #expect(NoteHighlightAnchoring.merged([0..<10, 10..<20]) == [0..<20])
        #expect(NoteHighlightAnchoring.merged([0..<5, 9..<20]) == [0..<5, 9..<20])
    }
}

// MARK: -

private extension String.Index {
    func utf8Offset(in string: String) -> Int {
        string.utf8.distance(from: string.utf8.startIndex, to: samePosition(in: string.utf8)!)
    }
}
