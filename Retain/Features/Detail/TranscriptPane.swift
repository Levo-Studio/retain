import SwiftUI

/// Board 04's left column: the full transcript with a find bar over it.
///
/// **A line is text, not a control.** It used to be a jump target into the
/// audio, and there is no audio: it is deleted once this transcript exists. A
/// row that still highlighted under the pointer and then did nothing would be
/// worse than a row that never invited the click, so the rows are plain and
/// what moves the pane is the find bar, a source chip, or a search hit arriving
/// from the library.
///
/// The timestamp stays. It is still when the sentence was said.
struct TranscriptPane: View {

    @Bindable var model: RecordingDetailModel

    var body: some View {
        VStack(spacing: 0) {
            findBar

            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RetainMetrics.transcriptMainLineGap) {
                        if model.lines.isEmpty {
                            Text(verbatim: DetailCopy.emptyTranscript)
                                .retainStyle(RetainTypography.transcriptLineMain)
                                .foregroundStyle(RetainPalette.inkDim)
                        } else {
                            ForEach(Array(model.lines.enumerated()), id: \.element.id) { index, line in
                                TranscriptRow(
                                    line: line,
                                    isMarked: isMarked(line),
                                    matches: model.find.ranges(inLineAt: index)
                                )
                                .id(line.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(RetainMetrics.transcriptPaneDetail)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.find) {
                    guard let line = model.lineToScrollTo else { return }
                    bring(line.id, into: scroll)
                }
                // A source chip, or a search hit opened from the library.
                //
                // `task(id:)` and not `onChange`: both of those bring this tab
                // forward, which builds this pane *after* the request was made
                // — a change `onChange` was never there for. The yield lets the
                // pane lay itself out before it is asked to scroll inside
                // itself.
                .task(id: model.reveal) {
                    guard case let .line(id) = model.reveal?.target else { return }
                    await Task.yield()
                    bring(id, into: scroll)
                }
            }
        }
        .background(RetainPalette.surfaceWindow)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Centred rather than at the top: a line is one sentence of a
    /// conversation, and it reads with what was said around it.
    private func bring(_ line: TranscriptLine.ID, into scroll: ScrollViewProxy) {
        withAnimation(RetainMotion.reveal(reduceMotion: reduceMotion)) {
            scroll.scrollTo(line, anchor: .center)
        }
    }

    /// A line the user marked while it was being said. The marker sits at a
    /// second, so the line it belongs to is the one that second falls inside.
    private func isMarked(_ line: TranscriptLine) -> Bool {
        model.annotations.contains { $0.time >= line.start && $0.time <= line.end }
    }

    // MARK: - The find bar

    private var findBar: some View {
        HStack(spacing: RetainMetrics.findBarGap) {
            RetainTextField(
                placeholder: DetailCopy.findPlaceholder,
                text: $model.findQuery,
                cornerRadius: RetainMetrics.radiusSearchField,
                padding: RetainMetrics.searchFieldPadding,
                onSubmit: { model.findNext() }
            )

            Text(verbatim: countLabel)
                .retainStyle(RetainTypography.findCount)
                .foregroundStyle(RetainPalette.inkLabel)

            arrow("↑", label: DetailCopy.findPrevious) { model.findPrevious() }
            arrow("↓", label: DetailCopy.findNext) { model.findNext() }
        }
        .padding(RetainMetrics.findBarPadding)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    private var countLabel: String {
        guard !model.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        guard let ordinal = model.find.currentOrdinal else { return DetailCopy.findNoMatches }
        return DetailCopy.findCount(current: ordinal, total: model.find.count)
    }

    private func arrow(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: glyph)
                .retainStyle(RetainTypography.findAction)
                .foregroundStyle(RetainPalette.inkBody)
        }
        .buttonStyle(RetainSurfaceButtonStyle())
        .disabled(model.find.count == 0)
        .accessibilityLabel(Text(verbatim: label))
    }
}

// MARK: - One line

/// `74px 1fr` — the second it was said at, then who said it and what they said.
struct TranscriptRow: View {

    let line: TranscriptLine
    let isMarked: Bool
    let matches: [Range<Int>]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isMarked {
                Rectangle()
                    .fill(RetainPalette.amber)
                    .frame(width: RetainMetrics.leftRuleWidth)
                    .padding(.trailing, RetainMetrics.leftRuleGapMain)
            }

            HStack(alignment: .top, spacing: RetainMetrics.transcriptLineGap) {
                Text(verbatim: RetainTimeFormat.clock(line.start))
                    .retainStyle(RetainTypography.timestampMain)
                    .foregroundStyle(isMarked ? RetainPalette.amberInk : RetainPalette.inkLabel)
                    .frame(width: RetainMetrics.transcriptTimestampColumn, alignment: .leading)
                    .padding(.top, RetainMetrics.transcriptLabelGapMain)

                VStack(alignment: .leading, spacing: RetainMetrics.transcriptLabelGapMain) {
                    Text(verbatim: speakerLabel)
                        .retainStyle(RetainTypography.uppercaseLabel)
                        .foregroundStyle(isMarked ? RetainPalette.amberInk : RetainPalette.inkLabel)

                    RetainSearchHitText(
                        text: line.text,
                        hits: matches,
                        style: RetainTypography.transcriptLineMain,
                        ink: isMarked ? RetainPalette.inkPrimary : RetainPalette.inkBody
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The rule hangs out into the pane's own padding, as the export draws
        // it, so the text under it stays on the same left edge as every
        // unmarked line.
        .padding(.leading, isMarked ? -RetainMetrics.transcriptMarkerRuleInset : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speakerLabel: String {
        let who = line.speaker == .audience ? DetailCopy.audience : DetailCopy.speaker
        return isMarked ? DetailCopy.markedLine(who) : who
    }
}

// MARK: - Painting the matches

/// Text with the find bar's hits behind it.
///
/// The export's search hit is a rounded rectangle with horizontal padding —
/// `oklch(.42 .09 95)`, 3px radius, `0 3px` — and `AttributedString`'s own
/// background attribute has neither a radius nor padding. So the same approach
/// `RetainMarkdownView` uses for the term highlight: mark the runs, and draw
/// the shapes behind the glyphs in a `TextRenderer`.
struct RetainSearchHitText: View {

    let text: String
    let hits: [Range<Int>]
    let style: RetainTextStyle
    let ink: Color

    var body: some View {
        composed
            .retainStyle(style)
            .foregroundStyle(ink)
            .textRenderer(Renderer())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var composed: Text {
        guard !hits.isEmpty else { return Text(verbatim: text) }

        let characters = Array(text)
        var pieces = Text(verbatim: "")
        var cursor = 0

        for hit in hits.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let start = min(max(hit.lowerBound, cursor), characters.count)
            let end = min(max(hit.upperBound, start), characters.count)
            if cursor < start {
                pieces = pieces + Text(verbatim: String(characters[cursor..<start]))
            }
            if start < end {
                pieces = pieces + Text(verbatim: String(characters[start..<end]))
                    .foregroundStyle(RetainPalette.searchHitInk)
                    .customAttribute(Mark())
            }
            cursor = end
        }
        if cursor < characters.count {
            pieces = pieces + Text(verbatim: String(characters[cursor...]))
        }
        return pieces
    }

    private struct Mark: TextAttribute {}

    private struct Renderer: TextRenderer {
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            for line in layout {
                for run in line where run[Mark.self] != nil {
                    let bounds = run.typographicBounds.rect
                        .insetBy(dx: -RetainMetrics.termHighlightPadding.leading, dy: 0)
                    context.fill(
                        Path(roundedRect: bounds, cornerRadius: RetainMetrics.radiusSearchHit),
                        with: .color(RetainPalette.searchHit)
                    )
                }
            }
            for line in layout {
                for run in line {
                    context.draw(run)
                }
            }
        }
    }
}
