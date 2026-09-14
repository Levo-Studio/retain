import SwiftUI

/// Board 03's left column: the written-out notes, with the annotations the user
/// typed during the lecture standing between them.
///
/// It is also where a chapter row and a chat citation land, which is why it
/// scrolls: with no audio to start playing, pointing at a block means putting
/// that block in front of the reader.
struct DetailNotesPane: View {

    let model: RecordingDetailModel

    var body: some View {
        ScrollViewReader { scroll in
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
            // `task(id:)` and not `onChange`: a chat citation clicked on the
            // transcript tab brings this tab forward, which builds this pane
            // *after* the request was made — a change `onChange` was never
            // there for. This fires on both, and the yield lets the pane lay
            // itself out before it is asked to scroll inside itself.
            .task(id: model.reveal) {
                guard case let .block(number) = model.reveal?.target else { return }
                await Task.yield()

                // The top, not the centre: a card is a heading and the text
                // under it, and it is read from its first line down.
                withAnimation(RetainMotion.reveal(reduceMotion: reduceMotion)) {
                    scroll.scrollTo(NoteItem.id(ofBlock: number), anchor: .top)
                }
            }
        }
        .background(RetainPalette.surfaceWindow)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            RetainAnnotationCard(
                label: DetailCopy.annotationLabel(time: RetainTimeFormat.clock(annotation.time)),
                text: annotation.note ?? "",
                layout: .detail
            )
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
