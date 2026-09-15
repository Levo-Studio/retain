import SwiftUI

// MARK: - Uppercase label

/// `.lbl` — the uppercase label above a value, above a rail, and at the top of
/// every popover card.
struct RetainLabel: View {

    let text: String
    var ink: Color = RetainPalette.inkLabel

    var body: some View {
        Text(verbatim: text)
            .retainStyle(RetainTypography.uppercaseLabel)
            .foregroundStyle(ink)
    }
}

// MARK: - Pause glyph

/// The two bars the export draws instead of an SF Symbol, at the two sizes it
/// draws them.
///
/// Only boards 01 and 02 have it, which is why it is here and not beside the
/// controls the whole app shares.
struct RetainPauseGlyph: View {

    let size: CGSize
    let colour: Color

    var body: some View {
        HStack(spacing: RetainMetrics.pauseGlyphGap) {
            bar
            bar
        }
        .accessibilityHidden(true)
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: RetainMetrics.pauseGlyphRadius)
            .fill(colour)
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Transcript line

/// One line of the live transcript, in a rail or in the popover.
///
/// The two differ only in their type sizes and in how far the audience rule
/// sits from the text, which is why they are one view with a size rather than
/// two views that will drift apart.
struct TranscriptLineRow: View {

    let line: TranscriptLine

    /// The recording window's rail sets 12.5/1.55, the popover 12.5/1.5.
    let bodyStyle: RetainTextStyle

    /// The rule's gap: 11 in a rail, 11 in the popover — the same, and named so
    /// because they are read from two different rows of the export.
    var ruleGap: CGFloat = RetainMetrics.leftRuleGapRail

    /// The newest line is brighter ink and carries the caret.
    var isNewest: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.transcriptLabelGapRail) {
            Text(verbatim: label)
                .retainStyle(RetainTypography.timestampRail)
                .foregroundStyle(labelInk)

            body(for: line.text)
        }
        .padding(.leading, line.speaker == .audience ? ruleGap : 0)
        .overlay(alignment: .leading) {
            if line.speaker == .audience {
                Rectangle()
                    .fill(RetainPalette.amber)
                    .frame(width: RetainMetrics.leftRuleWidth)
            }
        }
    }

    @ViewBuilder
    private func body(for text: String) -> some View {
        if isNewest {
            RetainCaretText(
                text: text,
                style: bodyStyle,
                ink: bodyInk,
                caret: RetainCaretStyle.rail(opacity:)
            )
        } else {
            Text(verbatim: text)
                .retainStyle(bodyStyle)
                .foregroundStyle(bodyInk)
        }
    }

    /// "00:46:03 · Speaker". Assembled from two catalog keys and the separator
    /// the export draws between them.
    private var label: String {
        "\(RetainTimeFormat.clock(line.start)) · \(Self.speakerName(line.speaker))"
    }

    static func speakerName(_ speaker: SpeakerRole) -> String {
        switch speaker {
        case .audience:
            String(localized: "Audience", comment: "Speaker of a transcript line that came from the room")
        case .lecturer, .unknown:
            // The live pass does not separate speakers — every line of it is
            // `.unknown` — and the design labels every line of the live
            // transcript "Lehrerin". Calling an unseparated line "Speaker" is
            // what the board draws and what is true most of the time.
            String(localized: "Speaker", comment: "Speaker of a transcript line, the person teaching")
        }
    }

    private var labelInk: Color {
        if line.speaker == .audience { return RetainPalette.amberInk }
        return isNewest ? RetainPalette.inkMuted : RetainPalette.inkLabel
    }

    private var bodyInk: Color {
        if line.speaker == .audience { return RetainPalette.inkBodyStrong }
        return isNewest ? RetainPalette.inkPrimary : RetainPalette.inkBody
    }
}
