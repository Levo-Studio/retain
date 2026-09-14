import Foundation
import Testing

@testable import Retain

@Suite("Block boundaries")
struct BlockBoundariesTests {

    /// Ten seconds of speech per line, back to back, which makes the arithmetic
    /// in each test readable: six lines are a minute.
    private func lines(_ count: Int, each: TimeInterval = 10, from start: TimeInterval = 0) -> [TranscriptLine] {
        (0..<count).map { index in
            TranscriptLine(
                start: start + Double(index) * each,
                end: start + Double(index) * each + each,
                text: "Satz \(index)"
            )
        }
    }

    private func marker(_ time: TimeInterval, _ text: String = "") -> RecordingMarker {
        RecordingMarker(time: time, text: text)
    }

    // MARK: - Nothing to cut

    @Test("No lines, no blocks")
    func emptyGivesNothing() {
        #expect(BlockBoundaries.blocks(from: []).isEmpty)
        #expect(BlockBoundaries.blocks(from: [], markers: [marker(10)]).isEmpty)
    }

    @Test("Less than a block's worth is still a block once the recording ends")
    func shortRecordingIsOneBlock() {
        let blocks = BlockBoundaries.blocks(from: lines(3))
        #expect(blocks.count == 1)
        #expect(blocks[0].closing == .endOfRecording)
        #expect(blocks[0].number == 1)
        #expect(blocks[0].lines.count == 3)
    }

    @Test("While the recording runs the trailing block stays open")
    func tailIsOpenDuringTheRecording() {
        let blocks = BlockBoundaries.blocks(from: lines(3), finished: false)
        #expect(blocks.count == 1)
        #expect(blocks[0].closing == .open)
        #expect(blocks[0].isOpen)
        #expect(BlockBoundaries.closed(blocks).isEmpty)
    }

    // MARK: - The budget

    @Test("Three minutes of speech closes a block")
    func budgetClosesABlock() {
        // Eighteen ten-second lines are exactly the budget, four more follow.
        let blocks = BlockBoundaries.blocks(from: lines(22))

        #expect(blocks.count == 2)
        #expect(blocks[0].closing == .speechBudget)
        #expect(blocks[0].lines.count == 18)
        #expect(blocks[0].speechDuration == BlockBoundaries.speechBudget)
        #expect(blocks[1].closing == .endOfRecording)
        #expect(blocks[1].lines.count == 4)
    }

    /// The reason the rule is written in speech and not in wall clock. A class
    /// working quietly for ten minutes produces no speech, and measuring the
    /// clock would close three blocks with nothing in them.
    @Test("Ten minutes of silence does not close anything")
    func silenceDoesNotCloseABlock() {
        let quiet = [
            TranscriptLine(start: 0, end: 5, text: "Fangt bitte mit Aufgabe drei an."),
            TranscriptLine(start: 600, end: 605, text: "Noch zwei Minuten."),
            TranscriptLine(start: 1200, end: 1205, text: "Wer hat ein Ergebnis?"),
        ]

        let blocks = BlockBoundaries.blocks(from: quiet)
        #expect(blocks.count == 1)
        #expect(blocks[0].speechDuration == 15)
        // Twenty minutes of wall clock in a single block, which is correct.
        #expect(blocks[0].end - blocks[0].start == 1205)
    }

    @Test("A long recording comes out as consecutively numbered blocks")
    func numbersAreConsecutive() {
        let blocks = BlockBoundaries.blocks(from: lines(100))
        #expect(blocks.count == 6)
        #expect(blocks.map(\.number) == Array(1...6))
    }

    @Test("Every line lands in exactly one block, in order")
    func nothingIsLostOrDuplicated() {
        let source = lines(97)
        let blocks = BlockBoundaries.blocks(from: source, markers: [marker(300), marker(900)])

        #expect(blocks.flatMap(\.lines) == source)
        for (previous, next) in zip(blocks, blocks.dropFirst()) {
            #expect(previous.end <= next.start)
        }
    }

    // MARK: - Markers

    @Test("A marker closes the block early")
    func markerClosesEarly() {
        // The marker lands inside the sixth line, by which point sixty seconds
        // of speech have accumulated — over the floor, well under the budget.
        let blocks = BlockBoundaries.blocks(from: lines(12), markers: [marker(52, "kommt in der Klausur")])

        #expect(blocks.count == 2)
        #expect(blocks[0].closing == .marker)
        #expect(blocks[0].lines.count == 6)
        #expect(blocks[0].markers.count == 1)
        #expect(blocks[1].markers.isEmpty)
    }

    /// Without the floor this is two cards, the first summarising one sentence.
    @Test("A marker in the first seconds waits for something to summarise")
    func markerBelowTheFloorDoesNotClose() {
        let blocks = BlockBoundaries.blocks(from: lines(12), markers: [marker(12, "wichtig")])

        #expect(blocks.count == 2)
        // Closed at the fifth line, the first one at which fifty seconds of
        // speech have accumulated.
        #expect(blocks[0].lines.count == 5)
        #expect(blocks[0].closing == .marker)
        #expect(blocks[0].markers.count == 1)
    }

    @Test("Two markers moments apart close one block, not two")
    func burstsOfMarkersMakeOneBlock() {
        let blocks = BlockBoundaries.blocks(
            from: lines(12),
            markers: [marker(52, "erstens"), marker(57, "und zweitens")]
        )

        #expect(blocks.count == 2)
        #expect(blocks[0].markers.count == 2)
        #expect(blocks[0].closing == .marker)
    }

    /// The invariant the floor exists for, over a recording full of markers: a
    /// card the model is asked to write always has something in it.
    @Test("No marker ever produces a block below the floor")
    func markerBlocksAreNeverTiny() {
        let pressed = (0..<20).map { marker(Double($0) * 13 + 5, "wichtig") }
        let blocks = BlockBoundaries.blocks(from: lines(60), markers: pressed)

        #expect(blocks.contains { $0.closing == .marker })
        for block in blocks where block.closing == .marker {
            #expect(block.speechDuration >= BlockBoundaries.minimumSpeech)
        }
    }

    @Test("A marker before anyone has spoken belongs to the first block")
    func markerBeforeTheFirstLine() {
        let blocks = BlockBoundaries.blocks(from: lines(4), markers: [marker(-3, "Titel der Stunde")])
        #expect(blocks[0].markers.count == 1)
    }

    @Test("A marker after the last word belongs to the last block")
    func markerAfterTheLastLine() {
        // Twenty lines: the first block closes on the budget, and the marker
        // arrives after everything has been said.
        let blocks = BlockBoundaries.blocks(from: lines(20), markers: [marker(5_000, "nachreichen")])

        #expect(blocks.count == 2)
        #expect(blocks[0].markers.isEmpty)
        #expect(blocks[1].markers.count == 1)
    }

    /// A marker arriving in the last line of a block that has already run its
    /// full length. There is no block after it to hold the marker.
    @Test("A marker with no block after it is not dropped")
    func trailingMarkerSurvivesAClosedTail() {
        let blocks = BlockBoundaries.blocks(from: lines(18), markers: [marker(179, "letzter Hinweis")])

        #expect(blocks.count == 1)
        #expect(blocks[0].markers.count == 1)
        #expect(blocks.flatMap(\.markers).count == 1)
    }

    @Test("Markers are not lost, duplicated or reordered")
    func markersArePreserved() {
        let all = [marker(700, "c"), marker(100, "a"), marker(400, "b")]
        let blocks = BlockBoundaries.blocks(from: lines(100), markers: all)

        let collected = blocks.flatMap(\.markers)
        #expect(collected.count == 3)
        #expect(collected.map(\.text) == ["a", "b", "c"])
    }

    /// The budget and a marker can both be true at the end of the same line.
    /// The block ran its full length, so that is what it says.
    @Test("A block that ran its full length says so even with a marker in it")
    func budgetWinsTheReason() {
        let blocks = BlockBoundaries.blocks(from: lines(22), markers: [marker(175, "kurz vor Schluss")])

        #expect(blocks[0].closing == .speechBudget)
        #expect(blocks[0].markers.count == 1)
    }

    // MARK: - Configuration

    @Test("The budget and the floor are the values the rule is written in")
    func constantsMatchTheBrief() {
        #expect(BlockBoundaries.speechBudget == 180)
        #expect(BlockBoundaries.minimumSpeech < BlockBoundaries.speechBudget)
    }

    @Test("A shorter budget cuts more often")
    func budgetIsAdjustable() {
        let blocks = BlockBoundaries.blocks(from: lines(12), speechBudget: 30, minimumSpeech: 10)
        #expect(blocks.count == 4)
        #expect(blocks.allSatisfy { $0.closing == .speechBudget })
    }

    @Test("Zero-length lines do not count towards the budget")
    func zeroLengthLinesCountForNothing() {
        let empties = (0..<50).map { TranscriptLine(start: Double($0), end: Double($0), text: "?") }
        let blocks = BlockBoundaries.blocks(from: empties)

        #expect(blocks.count == 1)
        #expect(blocks[0].speechDuration == 0)
    }

    @Test("Closed drops the open block and keeps the rest")
    func closedFiltersTheOpenOne() {
        let blocks = BlockBoundaries.blocks(from: lines(40), finished: false)
        let closed = BlockBoundaries.closed(blocks)

        #expect(blocks.last?.isOpen == true)
        #expect(closed.count == blocks.count - 1)
        #expect(closed.allSatisfy { !$0.isOpen })
    }

    @Test("A block reads back as one string")
    func blockTextJoinsItsLines() {
        let blocks = BlockBoundaries.blocks(from: lines(3))
        #expect(blocks[0].text == "Satz 0 Satz 1 Satz 2")
    }
}
