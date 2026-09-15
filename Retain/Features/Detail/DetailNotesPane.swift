import SwiftUI

/// Board 03's left column: the written-out notes.
///
/// It is also where a chapter row and a chat citation land, which is why it
/// scrolls: with no audio to start playing, pointing at a block means putting
/// that block in front of the reader. And it scrolls the other way too — the
/// rail's accent rule follows the reader down the page, which is `tops` and
/// `NotesScroll` below.
struct DetailNotesPane: View {

    let model: RecordingDetailModel

    /// The scroll view's own space, for measuring where the blocks sit in the
    /// visible area rather than in the content.
    ///
    /// `nonisolated` because the geometry transform below is `@Sendable` — the
    /// view is on the main actor by default, and a main-actor constant read
    /// from a `@Sendable` closure through a `@preconcurrency` declaration is
    /// how this app trapped at runtime twice already.
    nonisolated private static let space = "notes"

    /// Each block's number against the y of its top edge. Filled by the
    /// geometry reader on each card and read by nothing else.
    @State private var tops: [Int: CGFloat] = [:]

    /// The steps, while the model is working — **wherever it is working from**.
    ///
    /// It used to live inside the empty state, so it appeared only for a
    /// recording that had no notes. Pressing Re-analyse on a recording that
    /// already had some showed nothing at all: the old notes stayed on screen,
    /// unchanged, for as long as the model took, and then swapped. Working and
    /// idle looked identical, which is the version of this that gets reported
    /// as the button doing nothing.
    ///
    /// It takes the notes column and not the window, because that is the part
    /// of the screen that is about to change.
    @ViewBuilder
    private var working: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.detailEmptyNotesGap) {
            HStack(spacing: RetainMetrics.processingRowGap) {
                TypingIndicator()
                    .frame(width: RetainMetrics.processingMarkerColumn, alignment: .leading)

                Text(verbatim: ProcessingCopy.writingNotes)
                    .retainStyle(RetainTypography.fieldText)
                    .foregroundStyle(RetainPalette.inkPrimary)
            }

            Text(verbatim: DetailCopy.readingTranscript(lines: model.lines.count))
                .retainStyle(RetainTypography.captionSmall)
                .foregroundStyle(RetainPalette.inkLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What stands in for the notes when there are none.
    ///
    /// The sentence alone was the whole of it, and it left a reader with a full
    /// transcript, no notes, and nothing to do about either.
    @ViewBuilder
    private var empty: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.detailEmptyNotesGap) {
            Text(verbatim: DetailCopy.emptyNotes)
                .retainStyle(RetainTypography.noteParagraphDetail)
                .foregroundStyle(RetainPalette.inkDim)

            writeButton

            if case .failed(let reason) = model.noteWriting {
                Text(verbatim: reason)
                    .retainStyle(RetainTypography.captionSmall)
                    .foregroundStyle(RetainPalette.redInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var writeButton: some View {
        Button {
            Task { await model.writeNotes() }
        } label: {
            Text(verbatim: DetailCopy.writeNotes)
        }
        // The accent button, not the outlined one. It is the only thing to do
        // on an empty notes column, and it was drawn as quietly as the Export
        // button in the title bar — quiet enough that the owner looked at it
        // and asked where the button was.
        .buttonStyle(RetainPrimaryButtonStyle())
        .disabled(!model.canWriteNotes)
        .fixedSize()
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if case .running = model.noteWriting {
                        working
                    } else if model.blocks.isEmpty {
                        empty
                    } else {
                        ForEach(Array(model.noteItems.enumerated()), id: \.element.id) { index, item in
                            view(for: item)
                                .padding(.top, topGap(for: item, at: index))
                                .onGeometryChange(for: CGFloat.self) { @Sendable proxy in
                                    proxy.frame(in: .named(Self.space)).minY
                                } action: { top in
                                    if case let .block(block) = item { tops[block.number] = top }
                                }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RetainMetrics.notesPaneDetail)
            }
            .coordinateSpace(.named(Self.space))
            .scrollContentBackground(.hidden)
            // The rail follows the reader. `tops` changes on every frame of a
            // scroll, and the model refuses a number it is already on, so this
            // is one comparison per frame and a write only when the rule
            // actually moves.
            .onChange(of: tops) { _, measured in
                model.reader(reached: NotesScroll.block(at: RetainMetrics.notesReadingLine, tops: measured))
            }
            // Notes written again are different blocks at different heights,
            // and a measurement of the old ones would point the rail at a card
            // that is no longer there.
            .onChange(of: model.blocks.map(\.number)) { _, _ in tops = [:] }
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
        }
    }

    /// The renderer spaces its own elements; this is the air between one card
    /// and the next thing in the column.
    private func topGap(for item: NoteItem, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        switch item {
        case .block: return RetainMetrics.noteBlockGapDetail
        }
    }
}

// MARK: - "You · 00:52:10"

/// What the user typed during the lecture, behind the blue rule the export
/// reserves for everything that is theirs rather than the model's.
