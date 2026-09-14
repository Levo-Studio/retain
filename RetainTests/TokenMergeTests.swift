import Foundation
import Testing

@testable import Retain

@Suite("Token merge")
struct TokenMergeTests {

    private typealias Timed = (token: String, start: TimeInterval, end: TimeInterval)

    private func timed(_ pieces: [(String, TimeInterval, TimeInterval)]) -> [Timed] {
        pieces.map { (token: $0.0, start: $0.1, end: $0.2) }
    }

    @Test("Nothing in, nothing out")
    func emptyGivesNothing() {
        #expect(TokenMerge.words(from: []).isEmpty)
    }

    @Test("A word split across pieces comes back whole")
    func joinsSubwordPieces() {
        // What Parakeet actually does to a German compound.
        let words = TokenMerge.words(from: timed([
            ("\u{2581}Seiten", 1.0, 1.3),
            ("tabelle", 1.3, 1.6),
        ]))

        #expect(words.count == 1)
        #expect(words[0].text == "Seitentabelle")
        #expect(words[0].start == 1.0)
        #expect(words[0].end == 1.6)
    }

    @Test("The word takes the first piece's start and the last piece's end")
    func spansTheWholeWord() {
        let words = TokenMerge.words(from: timed([
            ("\u{2581}Ver", 2.0, 2.1),
            ("dräng", 2.1, 2.3),
            ("ung", 2.3, 2.5),
        ]))

        #expect(words == [WordTiming(text: "Verdrängung", start: 2.0, end: 2.5)])
    }

    @Test("Several words in a row stay separate")
    func separatesWords() {
        let words = TokenMerge.words(from: timed([
            ("\u{2581}Der", 0.0, 0.2),
            ("\u{2581}virtuelle", 0.2, 0.6),
            ("\u{2581}Adress", 0.6, 0.9),
            ("raum", 0.9, 1.1),
        ]))

        #expect(words.map(\.text) == ["Der", "virtuelle", "Adressraum"])
        #expect(words.last?.end == 1.1)
    }

    @Test("Language tags and other bookkeeping never reach the transcript")
    func dropsSpecialTokens() {
        let words = TokenMerge.words(from: timed([
            ("<de-DE>", 0.0, 0.0),
            ("\u{2581}Guten", 0.1, 0.4),
            ("<blank>", 0.4, 0.4),
            ("\u{2581}Morgen", 0.5, 0.9),
            ("<pad>", 0.9, 0.9),
        ]))

        #expect(words.map(\.text) == ["Guten", "Morgen"])
    }

    @Test("A word starting mid-stream without a boundary mark still becomes a word")
    func handlesAMissingLeadingBoundary() {
        // The first piece of a chunk can arrive without the marker.
        let words = TokenMerge.words(from: timed([
            ("tabelle", 1.0, 1.2),
            ("\u{2581}bildet", 1.2, 1.5),
        ]))

        #expect(words.map(\.text) == ["tabelle", "bildet"])
    }

    /// A piece whose end time comes back before the one before it must not pull
    /// the word's end backwards, or the line's duration goes negative and the
    /// seek target goes with it.
    @Test("An out-of-order piece cannot shorten the word")
    func endNeverGoesBackwards() {
        let words = TokenMerge.words(from: timed([
            ("\u{2581}Working", 5.0, 5.4),
            ("set", 5.4, 5.2),
        ]))

        #expect(words.count == 1)
        #expect(words[0].end == 5.4)
        #expect(words[0].end >= words[0].start)
    }

    @Test("Empty and whitespace-only pieces produce no word")
    func dropsEmptyPieces() {
        let words = TokenMerge.words(from: timed([
            ("\u{2581}", 0.0, 0.1),
            ("\u{2581}   ", 0.1, 0.2),
            ("\u{2581}echt", 0.2, 0.5),
        ]))

        #expect(words.map(\.text) == ["echt"])
    }

    @Test("A lone angle bracket is text, not bookkeeping")
    func doesNotOvermatchSpecialTokens() {
        #expect(TokenMerge.isSpecial("<") == false)
        #expect(TokenMerge.isSpecial("<>") == false)
        #expect(TokenMerge.isSpecial("<de-DE>"))
        #expect(TokenMerge.isSpecial("\u{2581}<blank>"))
        #expect(TokenMerge.isSpecial("kleiner") == false)
    }

    @Test("Words feed straight into line assembly")
    func feedsTheAssembly() {
        // The two pure steps have to compose, because in the real pipeline
        // nothing sits between them.
        let words = TokenMerge.words(from: timed([
            ("\u{2581}Der", 0.0, 0.2),
            ("\u{2581}TLB", 0.2, 0.5),
            ("\u{2581}hält", 0.5, 0.8),
        ]))
        let lines = TranscriptAssembly.lines(from: words)

        #expect(lines.count == 1)
        #expect(lines[0].text == "Der TLB hält")
    }
}

// MARK: -

/// FluidAudio's batch path runs every timing token through
/// `normalizedTimingToken`, which swaps U+2581 for a plain space before anyone
/// downstream sees it. Its streaming path does not. Matching only on U+2581
/// merged a whole lecture into one word and one line, which is what these
/// cover.
@Suite("Token merge, space-marked boundaries")
struct TokenMergeSpaceBoundaryTests {

    private typealias Timed = (token: String, start: TimeInterval, end: TimeInterval)

    private func timed(_ pieces: [(String, TimeInterval, TimeInterval)]) -> [Timed] {
        pieces.map { (token: $0.0, start: $0.1, end: $0.2) }
    }

    @Test("A leading space starts a word just as U+2581 does")
    func spaceIsAWordBoundary() {
        let words = TokenMerge.words(from: timed([
            (" Der", 0.0, 0.2),
            (" virtuelle", 0.2, 0.6),
            (" Adress", 0.6, 0.9),
            ("raum", 0.9, 1.1),
        ]))

        #expect(words.map(\.text) == ["Der", "virtuelle", "Adressraum"])
        #expect(words[2].start == 0.6)
        #expect(words[2].end == 1.1)
    }

    @Test("Both marker forms in one stream still split correctly")
    func mixedMarkersWork() {
        let words = TokenMerge.words(from: timed([
            ("\u{2581}Seiten", 0.0, 0.3),
            ("tabelle", 0.3, 0.6),
            (" bildet", 0.6, 0.9),
        ]))

        #expect(words.map(\.text) == ["Seitentabelle", "bildet"])
    }

    @Test("startsWord and stripBoundary agree on both forms")
    func markersAreRecognisedEitherWay() {
        #expect(TokenMerge.startsWord(" Wort"))
        #expect(TokenMerge.startsWord("\u{2581}Wort"))
        #expect(TokenMerge.startsWord("wort") == false)
        #expect(TokenMerge.startsWord("") == false)

        #expect(TokenMerge.stripBoundary(" Wort") == "Wort")
        #expect(TokenMerge.stripBoundary("\u{2581}Wort") == "Wort")
        #expect(TokenMerge.stripBoundary("wort") == "wort")
    }

    /// The exact failure: a minute of speech marked with spaces has to come
    /// back as many words, and the assembly has to cut it into several lines.
    @Test("A minute of space-marked tokens is many words and several lines")
    func aMinuteBecomesManyLines() {
        let tokens: [Timed] = (0..<300).map { index in
            let start = Double(index) * 0.2
            return (token: " wort\(index)", start: start, end: start + 0.2)
        }

        let words = TokenMerge.words(from: tokens)
        #expect(words.count == 300)

        let lines = TranscriptAssembly.lines(from: words)
        #expect(lines.count >= 3, "60 s of speech gave \(lines.count) line(s)")
    }
}
