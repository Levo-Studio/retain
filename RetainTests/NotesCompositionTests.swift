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

    /// The owner's instruction: a remark is not parked at the end of the notes
    /// in the words it was typed in. It goes to the model, which has to have
    /// worked its meaning into the section it belongs to — see
    /// `NoteReductionTests.reducePromptCarriesTheRemarks`.
    @Test("Annotations are not drawn in the notes column")
    func annotationsAreNotDrawn() {
        let items = NotesComposition.items(
            blocks: blocks,
            annotations: [
                annotation(1, at: 10, "ganz früh"),
                annotation(2, at: 3130, "Übungsblatt 5, Aufgabe 3 rechnet genau diesen Fall durch."),
                annotation(3, at: 9_000, "ganz spät"),
            ]
        )

        #expect(items == [.block(blocks[0]), .block(blocks[1])])
    }

    @Test("The cards are drawn in their own order, whatever order they arrive in")
    func cardsInOrder() {
        let items = NotesComposition.items(blocks: blocks.reversed(), annotations: [])
        #expect(items == [.block(blocks[0]), .block(blocks[1])])
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
