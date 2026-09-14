import Foundation
import Testing

@testable import Retain

// MARK: - Elapsed time

@Suite("Elapsed time")
struct ElapsedTimeTests {

    @Test("The timer is hh:mm:ss, zero padded", arguments: [
        (0.0, "00:00:00"),
        (9.0, "00:00:09"),
        (61.0, "00:01:01"),
        (2832.0, "00:47:12"),
        (3600.0, "01:00:00"),
        (36_000.0, "10:00:00"),
    ])
    func clockIsPadded(seconds: TimeInterval, expected: String) {
        #expect(RetainTimeFormat.clock(seconds) == expected)
    }

    @Test("A second is only over when it is over")
    func clockTruncates() {
        // Rounding up would show 00:00:01 for the first frame of a recording,
        // which is a timer that is wrong the moment it appears.
        #expect(RetainTimeFormat.clock(0.9) == "00:00:00")
        #expect(RetainTimeFormat.clock(1.999) == "00:00:01")
    }

    @Test("Nothing negative reaches the screen")
    func clockClampsAtZero() {
        #expect(RetainTimeFormat.clock(-5) == "00:00:00")
        #expect(RetainTimeFormat.minutesElapsed(-5) == 0)
    }

    @Test("The hours never disappear")
    func clockKeepsItsWidth() {
        // A timer that loses its hours below an hour changes width, and
        // everything beside it in the title bar moves with it.
        #expect(RetainTimeFormat.clock(59).count == RetainTimeFormat.clock(7200).count)
    }

    @Test("Whole minutes round down", arguments: [
        (0.0, 0),
        (59.0, 0),
        (60.0, 1),
        (2832.0, 47),
        (2_819.9, 46),
    ])
    func minutesRoundDown(seconds: TimeInterval, expected: Int) {
        #expect(RetainTimeFormat.minutesElapsed(seconds) == expected)
    }
}

// MARK: - The opacity ladder

@Suite("Transcript ladder")
struct TranscriptLadderTests {

    private func lines(_ count: Int) -> [TranscriptLine] {
        (0..<count).map {
            TranscriptLine(start: Double($0), end: Double($0) + 1, text: "line \($0)")
        }
    }

    @Test("The recording rail fades five lines the way the README lists them")
    func railLadder() {
        let rungs = TranscriptLadder.visible(lines(5), opacities: RetainMetrics.transcriptRailOpacities)
        #expect(rungs.map(\.opacity) == [0.5, 0.75, 1, 1, 1])
    }

    @Test("The popover fades three")
    func popoverLadder() {
        let rungs = TranscriptLadder.visible(lines(3), opacities: RetainMetrics.transcriptPopoverOpacities)
        #expect(rungs.map(\.opacity) == [0.55, 0.8, 1])
    }

    @Test("Only the last few lines are shown")
    func ladderTakesTheEnd() {
        let rungs = TranscriptLadder.visible(lines(20), opacities: RetainMetrics.transcriptRailOpacities)
        #expect(rungs.count == 5)
        #expect(rungs.map(\.line.text) == ["line 15", "line 16", "line 17", "line 18", "line 19"])
    }

    @Test("The newest line is always full strength, however few there are")
    func ladderReadsFromTheEnd() {
        // Two lines take the last two rungs, not the first two: the ladder is
        // about how old a line is, and the newest one is never faded.
        let rungs = TranscriptLadder.visible(lines(2), opacities: RetainMetrics.transcriptRailOpacities)
        #expect(rungs.map(\.opacity) == [1, 1])

        let one = TranscriptLadder.visible(lines(1), opacities: RetainMetrics.transcriptPopoverOpacities)
        #expect(one.map(\.opacity) == [1])
    }

    @Test("An empty transcript draws nothing")
    func ladderOfNothing() {
        #expect(TranscriptLadder.visible([], opacities: RetainMetrics.transcriptRailOpacities).isEmpty)
    }
}

// MARK: - The level meter

@Suite("Level meter")
struct LevelMeterTests {

    @Test("The history is as long as the meter has bars, and starts flat")
    func historyStartsFlat() {
        let history = RetainLevelHistory(capacity: RetainMetrics.meterBarCountPopover)
        #expect(history.fractions.count == RetainMetrics.meterBarCountPopover)
        #expect(history.fractions.allSatisfy { $0 == 0 })
    }

    @Test("A reading goes in at the newest end and pushes the oldest out")
    func historyRolls() {
        var history = RetainLevelHistory(capacity: 3)
        history.record(0.1)
        history.record(0.2)
        history.record(0.3)
        #expect(history.fractions == [0.1, 0.2, 0.3])
        history.record(0.4)
        #expect(history.fractions == [0.2, 0.3, 0.4])
        #expect(history.newest == 0.4)
    }

    @Test("A reading outside the scale is clamped onto it")
    func historyClamps() {
        var history = RetainLevelHistory(capacity: 2)
        history.record(4)
        history.record(-1)
        #expect(history.fractions == [1, 0])
    }

    @Test("A bar is never shorter than it is wide")
    func barsKeepAMinimum() {
        // A rounded rect of zero height disappears, and a meter that empties
        // out reads as a microphone that has stopped rather than a quiet room.
        #expect(RetainLevelMeter.barHeight(for: 0, in: 20) == RetainMetrics.waveformBarWidth)
        #expect(RetainLevelMeter.barHeight(for: 1, in: 20) == 20)
        #expect(RetainLevelMeter.barHeight(for: 0.5, in: 20) == 10)
    }

    @Test("A paused meter is one flat colour")
    func pausedMeterIsFlat() {
        let colours = (0..<RetainMetrics.meterBarCountPopover).map {
            RetainLevelMeter.colour(atIndex: $0, of: RetainMetrics.meterBarCountPopover, appearance: .paused)
        }
        #expect(Set(colours).count == 1)
        #expect(colours[0] == RetainPalette.waveformBarPaused)
    }

    @Test("The seventeen-bar meter colours the last five and nothing else")
    func popoverMeterRamp() {
        let count = RetainMetrics.meterBarCountPopover
        let colours = (0..<count).map { RetainLevelMeter.colour(atIndex: $0, of: count, appearance: .live) }

        // Exactly what the export paints: eleven idle bars, one a step
        // lighter, then the ramp centred on the middle of the coloured group.
        #expect(colours[0..<11].allSatisfy { $0 == RetainPalette.waveformBarIdle })
        #expect(colours[11] == RetainPalette.waveformBarRecent)
        #expect(Array(colours[12...]) == [
            RetainPalette.accentStep3,
            RetainPalette.accentStep2,
            RetainPalette.accent,
            RetainPalette.accentStep2,
            RetainPalette.accentStep3,
        ])
    }

    @Test("The five-bar meter is all ramp, brightest in the middle")
    func titleBarMeterRamp() {
        let count = RetainMetrics.meterBarCountTitleBar
        let colours = (0..<count).map { RetainLevelMeter.colour(atIndex: $0, of: count, appearance: .live) }
        #expect(colours == [
            RetainPalette.accentStep3,
            RetainPalette.accentStep2,
            RetainPalette.accent,
            RetainPalette.accentStep2,
            RetainPalette.accentStep3,
        ])
    }

    @Test("A silent meter has no accent in it at all")
    func idleMeterHasNoAccent() {
        let count = RetainMetrics.meterBarCountReady
        let colours = (0..<count).map { RetainLevelMeter.colour(atIndex: $0, of: count, appearance: .idle) }
        #expect(colours.allSatisfy { $0 == RetainPalette.waveformBarIdle })
    }
}

// MARK: - Note blocks

@Suite("Note block layout")
struct NoteBlockLayoutTests {

    @Test("Block numbers are zero padded to two digits")
    func numbersArePadded() {
        #expect(NoteBlockLayout.number(1) == "01")
        #expect(NoteBlockLayout.number(9) == "09")
        #expect(NoteBlockLayout.number(12) == "12")
    }

    @Test("The heading is taken out of the Markdown, because the view draws it")
    func bodyDropsTheHeading() {
        let markdown = "## Address spaces are an agreement\n\nEvery process sees one.\n\n- 4 KiB pages"
        #expect(NoteBlockLayout.body(of: markdown) == "Every process sees one.\n\n- 4 KiB pages")
    }

    @Test("A card with no heading keeps all of its text")
    func bodyWithoutAHeading() {
        #expect(NoteBlockLayout.body(of: "Just a paragraph.") == "Just a paragraph.")
    }

    @Test("A card with nothing but a heading has no body")
    func bodyOfAHeadingAlone() {
        #expect(NoteBlockLayout.body(of: "## Page faults").isEmpty)
    }

    @Test("A marker is drawn inside the block it falls in")
    func markersFallIntoBlocks() {
        let block = NoteBlock(number: 2, markdown: "## Two", start: 180, end: 360)
        let markers = [
            RecordingMarker(time: 60, text: "in block one"),
            RecordingMarker(time: 200, text: "in block two"),
            RecordingMarker(time: 400, text: "after both"),
        ]
        #expect(NoteBlockLayout.markers(of: block, in: markers).map(\.text) == ["in block two"])
    }

    @Test("A marker with nothing typed into it is not drawn")
    func emptyMarkersAreNotDrawn() {
        // The hotkey opening a composer the user then leaves empty is a
        // legitimate marker, and it has nothing to show in the notes.
        let block = NoteBlock(number: 1, markdown: "## One", start: 0, end: 180)
        let markers = [RecordingMarker(time: 30, text: "   ")]
        #expect(NoteBlockLayout.markers(of: block, in: markers).isEmpty)
        #expect(NoteBlockLayout.loose(markers, blocks: []).isEmpty)
    }

    @Test("Markers no block covers yet are drawn on their own")
    func looseMarkers() {
        // Everything marked since the last block closed, which with no
        // summariser configured is every marker there is.
        let blocks = [NoteBlock(number: 1, markdown: "## One", start: 0, end: 180)]
        let markers = [
            RecordingMarker(time: 30, text: "covered"),
            RecordingMarker(time: 240, text: "still open"),
        ]
        #expect(NoteBlockLayout.loose(markers, blocks: blocks).map(\.text) == ["still open"])
    }
}

// MARK: - The meta strip

@Suite("Meta strip")
struct MetaStripTests {

    @Test("The three columns keep the export's 1.6 : 1 : 1")
    func columnsKeepTheirRatio() {
        let widths = RecordingMetaStrip.columnWidths(in: 1120)
        #expect(widths.count == 3)
        #expect(abs(widths[1] - widths[2]) < 0.001)
        #expect(abs(widths[0] / widths[1] - 1.6) < 0.001)
    }

    @Test("The two rules between the columns come off the width first")
    func rulesAreTakenOffFirst() {
        // Otherwise the columns are two points wider than the strip and the
        // last one is clipped.
        let widths = RecordingMetaStrip.columnWidths(in: 1120)
        #expect(abs(widths.reduce(0, +) - (1120 - 2)) < 0.001)
    }

    @Test("A strip with no width in it does not go negative")
    func zeroWidthIsSafe() {
        #expect(RecordingMetaStrip.columnWidths(in: 0).allSatisfy { $0 == 0 })
    }
}

// MARK: - The power reading

@Suite("Power draw")
struct PowerDrawTests {

    @Test("Milliamps times millivolts is microwatts")
    func wattsFromTheRegisters() {
        // −2300 mA at 11.4 V is the 26 W a MacBook draws under a heavy load;
        // −750 mA at 11.4 V is the 8.6 W the export draws.
        #expect(abs(PowerDraw.watts(milliamps: -2300, millivolts: 11_400) - 26.22) < 0.001)
        #expect(abs(PowerDraw.watts(milliamps: -754, millivolts: 11_400) - 8.5956) < 0.001)
    }

    @Test("The reading is a magnitude, never a negative wattage")
    func wattsAreAlwaysPositive() {
        #expect(PowerDraw.watts(milliamps: -1000, millivolts: 11_000) == PowerDraw.watts(milliamps: 1000, millivolts: 11_000))
    }

    @Test("Only a discharging battery says what the machine is spending")
    func chargingIsNotDraw() {
        // A positive current is charge going in. Reading it as consumption
        // would put a number in the title bar that means something else.
        #expect(PowerDraw.isDischarging(milliamps: -754))
        #expect(!PowerDraw.isDischarging(milliamps: 1200))
        #expect(!PowerDraw.isDischarging(milliamps: 0))
    }
}

// MARK: - Motion

@Suite("Recording motion")
struct RecordingMotionTests {

    @Test("The sweep in the summarizing card stands still under Reduce Motion")
    func sweepStopsUnderReduceMotion() {
        #expect(RetainMotion.showsTravellingSweep(reduceMotion: false))
        #expect(!RetainMotion.showsTravellingSweep(reduceMotion: true))
        #expect(RetainMotion.animation(.sweep, reduceMotion: true) == nil)
    }

    @Test("The caret in the rail and the notes goes solid under Reduce Motion")
    func caretGoesSolid() {
        let moment = Date(timeIntervalSinceReferenceDate: 0.8)
        #expect(RetainMotion.caretOpacity(at: moment, reduceMotion: true) == 1)
        #expect(RetainMotion.caretOpacity(at: moment, reduceMotion: false) == 0)
    }

    @Test("Every loop the recording screen and the popover run is gated", arguments: [
        RetainMotion.Curve.recordingPulse,
        .breathe,
        .caret,
        .sweep,
    ])
    func everyLoopIsGated(curve: RetainMotion.Curve) {
        // The recording dot, the summarizing dot, the caret and the progress
        // bar are the four things these two boards animate, and all four reach
        // the screen through `RetainMotion`.
        #expect(RetainMotion.animation(curve, reduceMotion: true) == nil)
        #expect(RetainMotion.animation(curve, reduceMotion: false) != nil)
    }
}
