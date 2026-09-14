import SwiftUI

// MARK: - The caret

/// The blinking caret the export puts at the end of text that is still
/// arriving: the newest transcript line, and the note block the model is still
/// writing.
///
/// It is a geometry rather than a view because it is drawn inside a
/// `TextRenderer`, after the last glyph run of the last line. A caret that were
/// its own view could only sit beside a whole paragraph, and the export puts it
/// after the final word — which is a different place on every line break.
nonisolated struct RetainCaretStyle: Sendable, Equatable {

    let height: CGFloat
    let leadingGap: CGFloat
    let baselineDrop: CGFloat

    /// Set by whatever is driving the blink. `RetainMotion` decides it; this
    /// only carries it to the renderer.
    var opacity: Double

    var width: CGFloat { RetainMetrics.caretWidth }

    /// In the notes, where the text is 15px and the caret is too.
    static func notes(opacity: Double) -> RetainCaretStyle {
        RetainCaretStyle(
            height: RetainMetrics.caretHeightNotes,
            leadingGap: RetainMetrics.caretLeadingGapNotes,
            baselineDrop: RetainMetrics.caretBaselineDropNotes,
            opacity: opacity
        )
    }

    /// In a transcript rail, where everything is a size smaller.
    static func rail(opacity: Double) -> RetainCaretStyle {
        RetainCaretStyle(
            height: RetainMetrics.caretHeightRail,
            leadingGap: RetainMetrics.caretLeadingGapRail,
            baselineDrop: RetainMetrics.caretBaselineDropRail,
            opacity: opacity
        )
    }
}

// MARK: - Driving the blink

/// Hands its content the caret's opacity, and ticks only while the caret is
/// allowed to blink.
///
/// The timeline is anchored to the reference date rather than to `.now`, which
/// is the same clock `RetainMotion.caretIsVisible(at:)` reads: sampling on a
/// schedule that started whenever the view happened to appear would put the
/// step somewhere between the two halves of the period instead of on it.
///
/// Under Reduce Motion there is no `TimelineView` at all — not a timeline whose
/// value never changes. A view that redraws twice a second forever is still a
/// view that redraws twice a second forever.
struct RetainCaretTimeline<Content: View>: View {

    @ViewBuilder var content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(RetainMotion.caret.restingOpacity)
        } else {
            TimelineView(
                .periodic(
                    from: Date(timeIntervalSinceReferenceDate: 0),
                    by: RetainMotion.caret.period * RetainMotion.caret.visibleFraction
                )
            ) { context in
                content(RetainMotion.caretOpacity(at: context.date, reduceMotion: false))
            }
        }
    }
}

// MARK: - Text with a caret after it

/// One piece of prose with the caret at the end of it.
///
/// Used for the transcript line that is still forming. The note blocks go
/// through `RetainMarkdownView`, which takes the same style.
struct RetainCaretText: View {

    let text: String
    let style: RetainTextStyle
    let ink: Color

    /// `nil` draws the text alone, which is every line but the newest.
    let caret: (Double) -> RetainCaretStyle

    var body: some View {
        RetainCaretTimeline { opacity in
            Text(verbatim: text)
                .retainStyle(style)
                .foregroundStyle(ink)
                .textRenderer(RetainCaretRenderer(caret: caret(opacity)))
        }
    }
}

// MARK: - Drawing it

/// Paints the caret after the last glyph run of the last line.
///
/// Taking the trailing edge of that run rather than attaching the caret to a
/// character of its own is what keeps it in the right place through a line
/// break: there is no glyph to lay out, so nothing can wrap onto a line by
/// itself.
struct RetainCaretRenderer: TextRenderer {

    let caret: RetainCaretStyle

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                context.draw(run)
            }
        }

        guard let bounds = layout.last?.last?.typographicBounds else { return }

        let rect = CGRect(
            x: bounds.origin.x + bounds.width + caret.leadingGap,
            y: bounds.origin.y + caret.baselineDrop - caret.height,
            width: caret.width,
            height: caret.height
        )
        context.fill(
            Path(rect),
            with: .color(RetainPalette.redRecording.opacity(caret.opacity))
        )
    }
}
