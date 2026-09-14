import SwiftUI

/// Board 03's left column: the written-out notes, with the annotations the user
/// typed during the lecture standing between them.
struct NotesPane: View {

    let model: RecordingDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.blocks.isEmpty {
                    Text(verbatim: DetailCopy.emptyNotes)
                        .retainStyle(RetainTypography.noteParagraphDetail)
                        .foregroundStyle(RetainPalette.inkDim)
                } else {
                    ForEach(Array(model.noteItems.enumerated()), id: \.element.id) { index, item in
                        view(for: item)
                            .padding(.top, topGap(for: item, at: index))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RetainMetrics.notesPaneDetail)
        }
        .scrollContentBackground(.hidden)
        .background(RetainPalette.surfaceWindow)
    }

    @ViewBuilder
    private func view(for item: NoteItem) -> some View {
        switch item {
        case let .block(block):
            RetainMarkdownView(
                markdown: block.markdown,
                layout: .detail,
                highlights: model.highlightRanges[block.number] ?? [],
                highlightStyle: RetainNoteHighlightStyle(
                    background: RetainInteraction.highlightBackground,
                    cornerRadius: RetainInteraction.highlightCornerRadius,
                    horizontalPadding: RetainInteraction.highlightHorizontalPadding
                )
            )
        case let .annotation(annotation):
            AnnotationCard(annotation: annotation)
        }
    }

    /// The renderer spaces its own elements; this is the air between one card
    /// and the next thing in the column.
    private func topGap(for item: NoteItem, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        switch item {
        case .block: return RetainMetrics.noteBlockGapDetail
        case .annotation: return RetainMetrics.noteAnnotationGap
        }
    }
}

// MARK: - "You · 00:52:10"

/// What the user typed during the lecture, behind the blue rule the export
/// reserves for everything that is theirs rather than the model's.
struct AnnotationCard: View {

    let annotation: Annotation

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(RetainPalette.blue)
                .frame(width: RetainMetrics.leftRuleWidth)

            VStack(alignment: .leading, spacing: RetainMetrics.noteAnnotationLabelGap) {
                Text(verbatim: DetailCopy.annotationLabel(time: RetainTimeFormat.clock(annotation.time)))
                    .retainStyle(RetainTypography.uppercaseLabel)
                    .foregroundStyle(RetainPalette.blue)

                Text(verbatim: annotation.note ?? "")
                    .retainStyle(RetainTypography.annotationBody)
                    .foregroundStyle(RetainPalette.inkBodyStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, RetainMetrics.leftRuleGapMain)
        }
        .frame(maxWidth: measure, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `max-width:70ch`, in the paragraph font's own zero — the same measure
    /// the notes beside it are set to.
    private var measure: CGFloat {
        RetainTypography.chWidth(of: RetainTypography.noteParagraphDetail)
            * RetainMetrics.noteParagraphWidthDetail
    }
}
