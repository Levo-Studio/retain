import SwiftUI

/// A note the user typed themselves, set apart by a blue rule.
///
/// The export draws it twice — inside the notes column on board 01 while the
/// lecture runs, and between the finished cards on board 03 afterwards — and
/// draws it identically both times: the uppercase blue label "Von dir ·
/// 00:46:41", the body under it, and the 2px rule down the left.
///
/// It lives in the design layer rather than in either feature because it *is*
/// the same card. Two screens built it separately first, which is how two
/// `AnnotationCard` types ended up in one target, and the only thing they did
/// not agree on was the measure — which is the one thing the boards actually
/// draw differently.
///
/// Takes formatted strings rather than a model, so it belongs to neither the
/// recording's markers nor the stored annotations.
///
/// **Nothing draws it at the moment.** A remark the student types now goes to
/// the model instead of onto the page — see `NotesComposition.items` for why —
/// and this is the export's shape for it, kept in the design layer where the
/// export's shapes live rather than deleted and redrawn from the HTML if it is
/// ever asked for again.
struct RetainAnnotationCard: View {

    /// Which board's measure to set the body to.
    enum Layout {
        /// Board 01: the notes column beside the transcript rail, 64ch.
        case recording
        /// Board 03: the full-width detail pane, 70ch.
        case detail

        var paragraphStyle: RetainTextStyle {
            switch self {
            case .recording: RetainTypography.noteParagraphRecording
            case .detail: RetainTypography.noteParagraphDetail
            }
        }

        var measureInCharacters: CGFloat {
            switch self {
            case .recording: RetainMetrics.noteParagraphWidthRecording
            case .detail: RetainMetrics.noteParagraphWidthDetail
            }
        }
    }

    /// "You · 00:46:41", already assembled by the caller from its own catalog
    /// key — the two boards word it the same but the string belongs to a
    /// feature, not to the design layer.
    let label: String
    let text: String
    var layout: Layout = .detail

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(RetainPalette.blue)
                .frame(width: RetainMetrics.leftRuleWidth)

            VStack(alignment: .leading, spacing: RetainMetrics.noteAnnotationLabelGap) {
                Text(verbatim: label)
                    .retainStyle(RetainTypography.uppercaseLabel)
                    .foregroundStyle(RetainPalette.blue)

                Text(verbatim: text)
                    .retainStyle(RetainTypography.annotationBody)
                    .foregroundStyle(RetainPalette.inkBodyStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, RetainMetrics.leftRuleGapMain)
        }
        .frame(maxWidth: measure, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `max-width` in the paragraph font's own zero, which is what a CSS `ch`
    /// is — so the card wraps on the same measure as the notes beside it.
    private var measure: CGFloat {
        RetainTypography.chWidth(of: layout.paragraphStyle) * layout.measureInCharacters
    }
}
