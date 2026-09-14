import Foundation
import Testing

@testable import Retain

@Suite("Note markdown rendering")
struct RetainMarkdownTests {

    @Test("A heading becomes a heading")
    func aHeading() {
        let elements = RetainMarkdown.elements(of: "## Working Set und Thrashing")
        #expect(elements == [.heading([RetainInlineRun(text: "Working Set und Thrashing")])])
    }

    /// The model writes `##` and nothing else, but it does not always: a stray
    /// `#` or `###` is still a heading, because the alternative is drawing the
    /// hashes.
    @Test("Any heading level is the one heading the design draws")
    func everyHeadingLevelIsTheSameHeading() {
        for prefix in ["#", "##", "###", "####"] {
            #expect(RetainMarkdown.elements(of: "\(prefix) Titel") == [.heading([RetainInlineRun(text: "Titel")])])
        }
    }

    @Test("A paragraph becomes a paragraph")
    func aParagraph() {
        let elements = RetainMarkdown.elements(of: "Ein Page Fault ist der normale Weg.")
        #expect(elements == [.paragraph([RetainInlineRun(text: "Ein Page Fault ist der normale Weg.")])])
    }

    /// Wrapped lines are one paragraph, not three. A model that hard-wraps at
    /// eighty columns would otherwise get eighty-column paragraphs on screen.
    @Test("Consecutive lines are one paragraph")
    func wrappedLinesJoin() {
        let elements = RetainMarkdown.elements(of: "Erste Zeile\nzweite Zeile")
        #expect(elements == [.paragraph([RetainInlineRun(text: "Erste Zeile zweite Zeile")])])
    }

    @Test("A list becomes one list with its items in order")
    func aList() {
        let markdown = """
        - FIFO ist billig
        - Second Chance prüft das Referenzbit
        - Clock ist ein Ringpuffer
        """

        #expect(
            RetainMarkdown.elements(of: markdown) == [
                .bulletList([
                    [RetainInlineRun(text: "FIFO ist billig")],
                    [RetainInlineRun(text: "Second Chance prüft das Referenzbit")],
                    [RetainInlineRun(text: "Clock ist ein Ringpuffer")],
                ])
            ]
        )
    }

    @Test("A heading, a paragraph and a list in the order they were written")
    func aWholeBlock() {
        let markdown = """
        ## Adressräume

        Jeder Prozess sieht einen lückenlosen Adressraum.

        - Seitengröße 4 KiB
        """

        let elements = RetainMarkdown.elements(of: markdown)
        #expect(elements.count == 3)
        if case .heading = elements[0] {} else { Issue.record("first element is not a heading") }
        if case .paragraph = elements[1] {} else { Issue.record("second element is not a paragraph") }
        if case .bulletList = elements[2] {} else { Issue.record("third element is not a list") }
    }

    @Test("An emphasised term is its own run")
    func anEmphasisedTerm() {
        let elements = RetainMarkdown.elements(of: "Die **Seitentabelle** bildet ab.")

        #expect(
            elements == [
                .paragraph([
                    RetainInlineRun(text: "Die "),
                    RetainInlineRun(text: "Seitentabelle", isTerm: true),
                    RetainInlineRun(text: " bildet ab."),
                ])
            ]
        )
    }

    @Test("Both spellings of strong emphasis are the same term")
    func bothStrongSpellings() {
        let asterisks = RetainMarkdown.elements(of: "der **TLB** hält")
        let underscores = RetainMarkdown.elements(of: "der __TLB__ hält")
        #expect(asterisks == underscores)
    }

    /// There is no italic on any board, so a single marker is not turned into
    /// one. Leaving it as typed is the lesser wrong: the words are right and no
    /// style appears that was never designed.
    @Test("A single marker is left as typed")
    func singleMarkersAreNotEmphasis() {
        let elements = RetainMarkdown.elements(of: "a*b* c")
        #expect(elements == [.paragraph([RetainInlineRun(text: "a*b* c")])])
    }

    @Test("An unclosed marker is left as typed")
    func unclosedMarkersAreNotEmphasis() {
        let elements = RetainMarkdown.elements(of: "**TLB")
        #expect(elements == [.paragraph([RetainInlineRun(text: "**TLB")])])
    }

    /// The case the design does not draw and the model still produces: prose
    /// with no heading, no list and nothing emphasised. It has to come out as
    /// one paragraph rather than as nothing.
    @Test("Markdown with none of the three shapes is one paragraph")
    func plainProse() {
        let elements = RetainMarkdown.elements(of: "Nur Fließtext, ohne alles.")
        #expect(elements == [.paragraph([RetainInlineRun(text: "Nur Fließtext, ohne alles.")])])
    }

    @Test("Empty markdown renders nothing")
    func emptyMarkdown() {
        #expect(RetainMarkdown.elements(of: "").isEmpty)
        #expect(RetainMarkdown.elements(of: "\n\n  \n").isEmpty)
    }

    @Test("The plain text is what is read on screen, one line per thing")
    func plainTextIsWhatIsRead() {
        let markdown = """
        ## Titel

        Ein **Begriff** im Satz.

        - Erster Punkt
        - Zweiter Punkt
        """

        let text = RetainMarkdown.plainText(of: RetainMarkdown.elements(of: markdown))
        #expect(text == "Titel\nEin Begriff im Satz.\nErster Punkt\nZweiter Punkt")
    }

    // MARK: - Highlights

    /// Offsets are into the text as it is read, which is the text the user
    /// dragged over — the emphasis markers are not on screen to be selected.
    @Test("A highlight splits the runs it starts and ends inside")
    func aHighlightSplitsRuns() {
        let elements = RetainMarkdown.elements(of: "Der TLB hält alles.", highlights: [4..<7])

        #expect(
            elements == [
                .paragraph([
                    RetainInlineRun(text: "Der "),
                    RetainInlineRun(text: "TLB", isHighlighted: true),
                    RetainInlineRun(text: " hält alles."),
                ])
            ]
        )
    }

    /// The thing that has to be true for the two marks to coexist: a run over
    /// the same words carries both, so the term keeps its weight and ink and
    /// the highlight still gets its background.
    @Test("A highlight over a term leaves one run carrying both")
    func aHighlightOverATerm() {
        let elements = RetainMarkdown.elements(of: "Der **TLB** hält.", highlights: [4..<7])

        #expect(
            elements == [
                .paragraph([
                    RetainInlineRun(text: "Der "),
                    RetainInlineRun(text: "TLB", isTerm: true, isHighlighted: true),
                    RetainInlineRun(text: " hält."),
                ])
            ]
        )
    }

    @Test("A highlight that only covers part of a term splits it")
    func aPartialHighlightOverATerm() {
        let elements = RetainMarkdown.elements(of: "**Working Set**", highlights: [0..<7])

        #expect(
            elements == [
                .paragraph([
                    RetainInlineRun(text: "Working", isTerm: true, isHighlighted: true),
                    RetainInlineRun(text: " Set", isTerm: true),
                ])
            ]
        )
    }

    /// Offsets run across the whole block, counting the newline between one
    /// line and the next, or a highlight in the third bullet would land in the
    /// first.
    @Test("Offsets carry on across headings, paragraphs and list items")
    func offsetsSpanTheWholeBlock() {
        let markdown = """
        ## Titel

        Satz eins.

        - Punkt
        """

        let text = RetainMarkdown.plainText(of: RetainMarkdown.elements(of: markdown))
        guard let range = text.range(of: "Punkt") else {
            Issue.record("the fixture no longer contains the word")
            return
        }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)

        let elements = RetainMarkdown.elements(of: markdown, highlights: [start..<(start + 5)])
        #expect(
            elements.last == .bulletList([[RetainInlineRun(text: "Punkt", isHighlighted: true)]])
        )
    }

    @Test("No highlights leaves every run unmarked")
    func noHighlights() {
        let elements = RetainMarkdown.elements(of: "Der **TLB** hält.")
        let runs = elements.flatMap { element -> [RetainInlineRun] in
            if case let .paragraph(runs) = element { return runs }
            return []
        }
        #expect(runs.allSatisfy { !$0.isHighlighted })
    }
}
