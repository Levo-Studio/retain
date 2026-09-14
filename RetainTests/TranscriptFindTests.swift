import Foundation
import Testing

@testable import Retain

/// The find bar over the transcript: what it counts, and what its two arrows do
/// at the ends of the list.
@Suite("Transcript find")
struct TranscriptFindTests {

    private let lines = [
        TranscriptLine(start: 3014, end: 3040, text: "Bevor wir zum nächsten Punkt kommen: Was heißt eigentlich, ein Prozess braucht Speicher?"),
        TranscriptLine(start: 3062, end: 3070, text: "Nehmen wir an, der Prozess fasst in einer Sekunde vierzig Seiten an."),
        TranscriptLine(start: 3130, end: 3150, text: "Genau diese Menge nennen wir das Working Set. Es ist keine feste Zahl."),
        TranscriptLine(start: 3168, end: 3172, text: "Über welches Zeitfenster misst man das?", speaker: .audience),
        TranscriptLine(start: 3181, end: 3200, text: "Zu klein gewählt, sieht das Working Set künstlich klein aus, zu groß gewählt, schleppt man alte Seiten mit."),
    ]

    // MARK: - Counting

    @Test("An empty query matches nothing at all")
    func emptyQuery() {
        #expect(TranscriptFind(lines: lines, query: "").count == 0)
        #expect(TranscriptFind(lines: lines, query: "   ").count == 0)
        #expect(TranscriptFind(lines: lines, query: "").currentOrdinal == nil)
    }

    @Test("Every occurrence counts, including two in one line")
    func countsEveryOccurrence() {
        let find = TranscriptFind(lines: lines, query: "Prozess")
        #expect(find.count == 2)

        // "Seiten" is in lines 2 and 5, and "Seite" alone would also be inside
        // "Seiten" — the count is of occurrences, not of lines.
        let twice = TranscriptFind(lines: lines, query: "gewählt")
        #expect(twice.count == 2)
        #expect(twice.matches.allSatisfy { $0.lineIndex == 4 })
    }

    @Test("Matching ignores case and diacritics, because the transcript is German")
    func folding() {
        #expect(TranscriptFind(lines: lines, query: "working set").count == 2)
        #expect(TranscriptFind(lines: lines, query: "GEWAHLT").count == 2)
        #expect(TranscriptFind(lines: lines, query: "uber welches").count == 1)
    }

    @Test("A match knows which line it is in and where in the text")
    func offsets() throws {
        let find = TranscriptFind(lines: lines, query: "Working Set")
        let first = try #require(find.matches.first)

        #expect(first.lineIndex == 2)
        let text = Array(lines[2].text)
        #expect(String(text[first.range]) == "Working Set")
    }

    @Test("A query that matches starts on its first hit")
    func startsOnTheFirst() {
        #expect(TranscriptFind(lines: lines, query: "Working Set").currentOrdinal == 1)
    }

    // MARK: - Stepping

    @Test("The count reads as the export draws it: three of eleven")
    func ordinalAndTotal() {
        var find = TranscriptFind(lines: lines, query: "e")
        #expect(find.count > 3)

        find.moveToNext()
        find.moveToNext()
        #expect(find.currentOrdinal == 3)
    }

    @Test("Past the last match is the first one again")
    func wrapsForwards() {
        var find = TranscriptFind(lines: lines, query: "Working Set")
        #expect(find.count == 2)

        find.moveToNext()
        #expect(find.currentOrdinal == 2)
        find.moveToNext()
        #expect(find.currentOrdinal == 1)
    }

    @Test("Before the first match is the last one")
    func wrapsBackwards() {
        var find = TranscriptFind(lines: lines, query: "Working Set")

        find.moveToPrevious()
        #expect(find.currentOrdinal == 2)
        find.moveToPrevious()
        #expect(find.currentOrdinal == 1)
    }

    @Test("Stepping through nothing does nothing rather than trapping")
    func steppingWithNoMatches() {
        var find = TranscriptFind(lines: lines, query: "Bankiersalgorithmus")

        find.moveToNext()
        find.moveToPrevious()

        #expect(find.count == 0)
        #expect(find.currentOrdinal == nil)
        #expect(find.currentMatch == nil)
    }

    @Test("A line knows every match inside it, for painting them in place")
    func rangesPerLine() {
        let find = TranscriptFind(lines: lines, query: "gewählt")

        #expect(find.ranges(inLineAt: 4).count == 2)
        #expect(find.ranges(inLineAt: 0).isEmpty)
    }
}
