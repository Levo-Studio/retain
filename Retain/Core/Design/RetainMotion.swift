import Foundation
import SwiftUI

/// The four keyframes the export animates with, and the one place Reduce Motion
/// is decided.
///
/// Every animation in Retain goes through `resolve`. Not because a call site
/// could not read `accessibilityReduceMotion` itself, but because there will be
/// a hundred of them and ninety would forget — and a forgotten one is a pulsing
/// dot in the corner of the eye of somebody who asked the system, once, for
/// that to stop.
///
/// What Reduce Motion turns each of these into is the design README's answer,
/// not a guess: the caret goes solid, the pulse and breathe go to full opacity,
/// and the indeterminate sweep becomes a static determinate bar.
nonisolated enum RetainMotion {

    // MARK: - Curves

    /// Every decorative loop the export draws. `CaseIterable` on purpose: it is
    /// what lets a test walk all of them and assert that none of them moves
    /// under Reduce Motion, including one added after the test was written.
    enum Curve: String, Sendable, CaseIterable {
        /// `recpulse` — the recording dot.
        case recordingPulse
        /// `caret` — the blinking text caret.
        case caret
        /// `sweep` — indeterminate progress while summarizing.
        case sweep
        /// `breathe` — the status dot while summarizing.
        case breathe
        /// `breathe` again at 1.4s, three dots, staggered — the chat typing
        /// indicator.
        case typingIndicator
    }

    /// A loop between two opacities and back.
    nonisolated struct OpacityLoop: Sendable, Equatable {

        /// One full there-and-back cycle, as CSS writes it.
        let duration: Double
        let low: Double
        let high: Double

        /// Where the loop sits when it is not allowed to run.
        var restingOpacity: Double { high }
    }

    /// A step-end blink: visible for the first part of the period, hidden for
    /// the rest, with no fade in between.
    nonisolated struct Blink: Sendable, Equatable {

        let period: Double

        /// How much of the period the caret is visible for. The export writes
        /// `0%,49%{opacity:1} 50%,100%{opacity:0}` — visible through the first
        /// half, hidden through the second.
        let visibleFraction: Double

        /// Solid, under Reduce Motion.
        var restingOpacity: Double { 1 }
    }

    /// A bar travelling across its track without ever saying how far along the
    /// work is.
    nonisolated struct IndeterminateSweep: Sendable, Equatable {

        let duration: Double

        /// How wide the travelling bar is, as a fraction of the track.
        let barWidthFraction: Double

        /// Where it starts and ends, in multiples of its own width — CSS
        /// `translateX(-100%)` to `translateX(320%)`.
        let fromFraction: Double
        let toFraction: Double
    }

    // MARK: - The four, as drawn

    /// `recpulse` — 2s ease-in-out, opacity 1 → .25 → 1.
    static let recordingPulse = OpacityLoop(duration: 2, low: 0.25, high: 1)

    /// `breathe` — 1.6s ease-in-out, opacity .5 → 1 → .5.
    static let breathe = OpacityLoop(duration: 1.6, low: 0.5, high: 1)

    /// `breathe` at 1.4s, for the chat typing indicator.
    static let typingIndicator = OpacityLoop(duration: 1.4, low: 0.5, high: 1)

    /// The three dots start 0.2s apart, which is what makes it read as typing
    /// rather than as three things blinking.
    static let typingIndicatorDelays: [Double] = [0, 0.2, 0.4]

    /// `caret` — 1.1s step-end.
    static let caret = Blink(period: 1.1, visibleFraction: 0.5)

    /// `sweep` — 1.6s ease-in-out, a bar 30 % wide travelling from −100 % to
    /// 320 %.
    static let sweep = IndeterminateSweep(
        duration: 1.6,
        barWidthFraction: 0.3,
        fromFraction: -1,
        toFraction: 3.2
    )

    // MARK: - Bringing something into view

    /// How long a pane takes to scroll to the line or the card something
    /// pointed at.
    ///
    /// **Not a drawn value.** The export animates four things and scrolling is
    /// not one of them. It is the shortest move that still reads as a move
    /// rather than as the list having been replaced, and it lives here rather
    /// than in each pane so the transcript and the notes cannot drift apart.
    static let revealDuration: Double = 0.3

    /// The animation a pane scrolls with, or `nil` under Reduce Motion — where
    /// the target simply appears, which is the whole point of the setting.
    static func reveal(reduceMotion: Bool) -> Animation? {
        resolve(.easeInOut(duration: revealDuration), reduceMotion: reduceMotion)
    }

    // MARK: - The rail sliding out of the way

    /// How long the rail takes to fold away and come back.
    ///
    /// **Not a drawn value.** The export draws the rail and has no state
    /// without it. This is real work being shown — a column the width of the
    /// window is changing — so unlike a content swap it earns motion: fast
    /// enough not to be waited for, slow enough that the text reflowing reads
    /// as the rail moving rather than as the page being rebuilt.
    static let railDuration: Double = 0.24

    /// The animation the rail folds with, or `nil` under Reduce Motion, where
    /// it is simply gone.
    static func rail(reduceMotion: Bool) -> Animation? {
        resolve(.easeInOut(duration: railDuration), reduceMotion: reduceMotion)
    }

    // MARK: - Picking several at once

    /// How long the tick takes to appear in front of a row, and the title to
    /// move over for it.
    ///
    /// **Not a drawn value.** The export has no selection state. It is the
    /// shortest move that reads as the row making room rather than as the table
    /// being re-laid out, and it is one value rather than two so the tick and
    /// the title cannot arrive at different times.
    static let selectionDuration: Double = 0.18

    static func selection(reduceMotion: Bool) -> Animation? {
        resolve(.easeOut(duration: selectionDuration), reduceMotion: reduceMotion)
    }

    // MARK: - The gate

    /// The one place an animation is allowed to become no animation.
    ///
    /// Everything animated in Retain — these loops, and any state transition a
    /// screen adds later — goes through here. Returning `nil` rather than a
    /// zero-duration animation matters: `nil` is what SwiftUI takes as "change
    /// this value without animating it", and it cannot be accidentally
    /// re-enabled by a `.repeatForever` further down the chain.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// The animation for one of the drawn loops, or `nil` under Reduce Motion.
    static func animation(_ curve: Curve, delay: Double = 0, reduceMotion: Bool) -> Animation? {
        let animation: Animation

        switch curve {
        case .recordingPulse:
            animation = repeating(recordingPulse)
        case .breathe:
            animation = repeating(breathe)
        case .typingIndicator:
            animation = repeating(typingIndicator)
        case .caret:
            // Step-end has no interpolation in it at all: the value snaps, and
            // the timing comes from whatever drives the phase.
            animation = .linear(duration: 0)
        case .sweep:
            animation = .easeInOut(duration: sweep.duration).repeatForever(autoreverses: false)
        }

        return resolve(delay > 0 ? animation.delay(delay) : animation, reduceMotion: reduceMotion)
    }

    /// A there-and-back loop is half a cycle, auto-reversed.
    private static func repeating(_ loop: OpacityLoop) -> Animation {
        .easeInOut(duration: loop.duration / 2).repeatForever(autoreverses: true)
    }

    /// What a curve's opacity sits at when it is not allowed to move.
    static func restingOpacity(_ curve: Curve) -> Double {
        switch curve {
        case .recordingPulse: recordingPulse.restingOpacity
        case .breathe: breathe.restingOpacity
        case .typingIndicator: typingIndicator.restingOpacity
        case .caret: caret.restingOpacity
        case .sweep: 1
        }
    }

    /// The opacity to draw a curve at, given whether it is at the far end of
    /// its loop. Under Reduce Motion it is the resting value and nothing else.
    static func opacity(_ curve: Curve, atFarEnd: Bool, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return restingOpacity(curve) }

        switch curve {
        case .recordingPulse: return atFarEnd ? recordingPulse.low : recordingPulse.high
        case .breathe: return atFarEnd ? breathe.low : breathe.high
        case .typingIndicator: return atFarEnd ? typingIndicator.low : typingIndicator.high
        case .caret: return atFarEnd ? 0 : 1
        case .sweep: return 1
        }
    }

    /// Whether the summarizing progress bar may travel.
    ///
    /// `false` means the screen draws a determinate bar instead — the same
    /// track, filled to how far along the work actually is, standing still.
    static func showsTravellingSweep(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// Whether the caret is in its visible half at a given moment.
    ///
    /// A pure function of the clock rather than a piece of animation state, so
    /// a `TimelineView` can drive it and get the step exactly where the export
    /// puts it instead of a fade that approximates one.
    static func caretIsVisible(at date: Date) -> Bool {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: caret.period)
        return phase / caret.period < caret.visibleFraction
    }

    /// The caret's opacity at a moment: blinking, or solid under Reduce Motion.
    static func caretOpacity(at date: Date, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return caret.restingOpacity }
        return caretIsVisible(at: date) ? 1 : 0
    }
}

// MARK: - Applying a loop

/// Runs one of the drawn opacity loops on a view, and stands still when the
/// system asks it to.
private struct RetainLoopModifier: ViewModifier {

    let curve: RetainMotion.Curve
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var atFarEnd = false

    func body(content: Content) -> some View {
        content
            .opacity(RetainMotion.opacity(curve, atFarEnd: atFarEnd, reduceMotion: reduceMotion))
            .animation(
                RetainMotion.animation(curve, delay: delay, reduceMotion: reduceMotion),
                value: atFarEnd
            )
            .onAppear {
                guard !reduceMotion else { return }
                atFarEnd = true
            }
    }
}

extension View {

    /// Pulse, breathe or stagger a view the way the export draws it — and stop
    /// under Reduce Motion without the call site having to know.
    func retainLoop(_ curve: RetainMotion.Curve, delay: Double = 0) -> some View {
        modifier(RetainLoopModifier(curve: curve, delay: delay))
    }
}
