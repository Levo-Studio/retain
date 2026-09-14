import Foundation
import SwiftUI
import Testing

@testable import Retain

@Suite("Motion")
struct RetainMotionTests {

    /// The whole reason the gate exists. Walking `allCases` rather than listing
    /// the five means a curve added later is covered by this test before anyone
    /// remembers to add it.
    @Test("Nothing moves under Reduce Motion", arguments: RetainMotion.Curve.allCases)
    func nothingMovesUnderReduceMotion(curve: RetainMotion.Curve) {
        #expect(RetainMotion.animation(curve, reduceMotion: true) == nil)
        #expect(RetainMotion.animation(curve, delay: 0.4, reduceMotion: true) == nil)
    }

    @Test("Everything moves when it is allowed to", arguments: RetainMotion.Curve.allCases)
    func everythingMovesOtherwise(curve: RetainMotion.Curve) {
        #expect(RetainMotion.animation(curve, reduceMotion: false) != nil)
    }

    /// The resting value is not "whatever it happened to be when it stopped".
    /// The README says what each one settles at: the caret solid, the pulse and
    /// breathe at full opacity.
    @Test("Every curve rests somewhere visible", arguments: RetainMotion.Curve.allCases)
    func everyCurveRestsFullyVisible(curve: RetainMotion.Curve) {
        #expect(RetainMotion.restingOpacity(curve) == 1)
        #expect(RetainMotion.opacity(curve, atFarEnd: true, reduceMotion: true) == 1)
        #expect(RetainMotion.opacity(curve, atFarEnd: false, reduceMotion: true) == 1)
    }

    /// Without Reduce Motion the far end of a loop is the dim end, or the
    /// keyframes would be drawn as a flat line.
    @Test("A loop dips at its far end when it is allowed to run")
    func loopsDipWhenAllowed() {
        #expect(RetainMotion.opacity(.recordingPulse, atFarEnd: true, reduceMotion: false) == 0.25)
        #expect(RetainMotion.opacity(.breathe, atFarEnd: true, reduceMotion: false) == 0.5)
        #expect(RetainMotion.opacity(.typingIndicator, atFarEnd: true, reduceMotion: false) == 0.5)
        #expect(RetainMotion.opacity(.caret, atFarEnd: true, reduceMotion: false) == 0)
    }

    @Test("The four keyframes have the timings the export writes")
    func theTimings() {
        #expect(RetainMotion.recordingPulse == .init(duration: 2, low: 0.25, high: 1))
        #expect(RetainMotion.breathe == .init(duration: 1.6, low: 0.5, high: 1))
        #expect(RetainMotion.caret.period == 1.1)
        #expect(RetainMotion.sweep.duration == 1.6)
        #expect(RetainMotion.sweep.barWidthFraction == 0.3)
        #expect(RetainMotion.sweep.fromFraction == -1)
        #expect(RetainMotion.sweep.toFraction == 3.2)
    }

    /// The typing indicator is `breathe` slowed to 1.4s with the three dots
    /// 0.2s apart — that stagger is what makes it read as typing.
    @Test("The typing indicator is breathe at 1.4s, staggered")
    func theTypingIndicator() {
        #expect(RetainMotion.typingIndicator.duration == 1.4)
        #expect(RetainMotion.typingIndicator.low == RetainMotion.breathe.low)
        #expect(RetainMotion.typingIndicator.high == RetainMotion.breathe.high)
        #expect(RetainMotion.typingIndicatorDelays == [0, 0.2, 0.4])
    }

    /// Step-end, not a fade: visible through the first half of the period,
    /// hidden through the second, and nothing in between.
    @Test("The caret is on for half its period and off for the other half")
    func theCaretSteps() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(RetainMotion.caretIsVisible(at: start))
        #expect(RetainMotion.caretIsVisible(at: start.addingTimeInterval(0.54)))
        #expect(!RetainMotion.caretIsVisible(at: start.addingTimeInterval(0.56)))
        #expect(!RetainMotion.caretIsVisible(at: start.addingTimeInterval(1.09)))
        #expect(RetainMotion.caretIsVisible(at: start.addingTimeInterval(1.11)))
    }

    @Test("Under Reduce Motion the caret is solid at every moment")
    func theCaretGoesSolid() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for offset in stride(from: 0.0, through: 2.2, by: 0.05) {
            #expect(RetainMotion.caretOpacity(at: start.addingTimeInterval(offset), reduceMotion: true) == 1)
        }
    }

    /// The sweep is the one curve that does not just stop: an indeterminate bar
    /// standing still says nothing at all, so it becomes a determinate one.
    @Test("The sweep stops travelling under Reduce Motion")
    func theSweepBecomesDeterminate() {
        #expect(RetainMotion.showsTravellingSweep(reduceMotion: false))
        #expect(!RetainMotion.showsTravellingSweep(reduceMotion: true))
    }

    /// The gate is a gate for everything, not only the five drawn loops — a
    /// screen's own state transition goes through the same call.
    @Test("The gate turns any animation into no animation")
    func theGateIsGeneral() {
        #expect(RetainMotion.resolve(.easeInOut(duration: 0.3), reduceMotion: true) == nil)
        #expect(RetainMotion.resolve(.easeInOut(duration: 0.3), reduceMotion: false) == .easeInOut(duration: 0.3))
    }
}
