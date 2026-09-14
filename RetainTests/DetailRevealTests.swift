import Foundation
import Testing

@testable import Retain

/// Where a click in the recording detail takes the reader, now that there is no
/// audio for it to take them into.
@Suite("Revealing")
struct DetailRevealTests {

    private let blocks = [
        NoteBlock(number: 1, markdown: "## Wann eine Seite verdrängt werden darf\nAbsatz.", start: 240, end: 2940),
        NoteBlock(number: 2, markdown: "## Working Set und Thrashing\nAbsatz.", start: 2940, end: 5520),
    ]

    private let lines = [
        StoreFixture.line("Die Auswahl entscheidet über die Trefferrate.", at: 300, to: 306),
        StoreFixture.line("Das Working Set ist die Menge der Seiten.", at: 3130, to: 3138),
    ]

    // MARK: - A second in the transcript

    @Test("A second inside a line resolves to that line")
    func aSpokenSecond() {
        #expect(DetailReveal.line(at: 3134, in: lines) == lines[1].id)
    }

    /// A pause, or the stretch after the last word. The sentence that was being
    /// said is the one that ended there, not the one that had not started.
    @Test("A second in a gap resolves to the line before it")
    func aSilentSecond() {
        #expect(DetailReveal.line(at: 400, in: lines) == lines[0].id)
        #expect(DetailReveal.line(at: 9999, in: lines) == lines[1].id)
    }

    @Test("A second before the first word resolves to the first line")
    func beforeTheFirstLine() {
        #expect(DetailReveal.line(at: 0, in: lines) == lines[0].id)
    }

    @Test("A transcript that was never written resolves to nothing")
    func noLines() {
        #expect(DetailReveal.line(at: 3134, in: []) == nil)
    }

    // MARK: - A second in the notes

    @Test("A second inside a block resolves to that block")
    func aSecondInABlock() {
        #expect(DetailReveal.block(at: 3130, in: blocks) == 2)
        #expect(DetailReveal.block(at: 300, in: blocks) == 1)
    }

    @Test("A second before the first block resolves to the first one")
    func beforeTheFirstBlock() {
        #expect(DetailReveal.block(at: 0, in: blocks) == 1)
    }

    @Test("A recording with no notes has no block to point at")
    func noBlocks() {
        #expect(DetailReveal.block(at: 3130, in: []) == nil)
    }

    // MARK: - A source chip

    @Test("A transcript chip points at the line said at its second")
    func aTranscriptChip() {
        #expect(
            DetailReveal.target(for: .transcript(3134), lines: lines, blocks: blocks)
                == .line(lines[1].id)
        )
    }

    @Test("A note chip points at the card it cites")
    func aNoteChip() {
        #expect(
            DetailReveal.target(for: .note(2), lines: lines, blocks: blocks) == .block(2)
        )
    }

    /// The notes can be written again after an answer was, and a chip reading
    /// "Note 9" that lands at the top of the notes is worse than one that does
    /// nothing.
    @Test("A chip citing a note that no longer exists resolves to nothing")
    func aNoteChipForAMissingBlock() {
        #expect(DetailReveal.target(for: .note(9), lines: lines, blocks: blocks) == nil)
    }

    @Test("A transcript chip on a recording with no transcript resolves to nothing")
    func aTranscriptChipWithoutLines() {
        #expect(DetailReveal.target(for: .transcript(3134), lines: [], blocks: blocks) == nil)
    }

    // MARK: - Asking twice

    /// A pane watches the request and scrolls when it changes. Two requests for
    /// the same place have to differ, or the second click does nothing and the
    /// row looks broken.
    @Test("The same target asked for twice is two different requests")
    func repeatedRequestsDiffer() {
        let first = DetailReveal.Request(target: .block(2), ordinal: 1)
        let second = DetailReveal.Request(target: .block(2), ordinal: 2)

        #expect(first != second)
        #expect(first.target == second.target)
    }
}
