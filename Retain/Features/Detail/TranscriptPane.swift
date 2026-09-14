import SwiftUI

/// Board 04's left column: the full transcript with a find bar over it.
///
/// Every line is a jump target. That is the reason the transcript is kept at
/// all — the notes are what you read, and the transcript is what you go to when
/// the notes are not enough and you want to hear it said.
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
                                ) {
                                    model.play(line: line)
                                }
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
                    withAnimation(RetainMotion.resolve(.easeInOut(duration: scrollDuration), reduceMotion: reduceMotion)) {
                        scroll.scrollTo(line.id, anchor: .center)
                    }
                }
            }
        }
        .background(RetainPalette.surfaceWindow)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Not a drawn value: the export animates four things and scrolling is not
    /// one of them. It is the shortest move that still reads as a move rather
    /// than as the list having been replaced.
    private let scrollDuration: Double = 0.3

    /// A line the user marked while it was being said. The marker sits at a
    /// second, so the line it belongs to is the one that second falls inside.
    private func isMarked(_ line: TranscriptLine) -> Bool {
        model.annotations.contains { $0.time >= line.start && $0.time <= line.end }
    }

    // MARK: - The find bar

    private var findBar: some View {
        HStack(spacing: RetainMetrics.findBarGap) {
            TextField(text: $model.findQuery) {
                Text(verbatim: DetailCopy.findPlaceholder)
            }
            .textFieldStyle(.plain)
            .retainStyle(RetainTypography.fieldText)
            .foregroundStyle(RetainPalette.inkPrimary)
            .padding(RetainMetrics.searchFieldPadding)
            .background {
                RoundedRectangle(cornerRadius: RetainMetrics.radiusSearchField, style: .continuous)
                    .fill(RetainPalette.surfaceInsetControl)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RetainMetrics.radiusSearchField, style: .continuous)
                    .strokeBorder(fieldBorder, lineWidth: 1)
            }

            Text(verbatim: countLabel)
                .retainStyle(RetainTypography.findCount)
                .foregroundStyle(RetainPalette.inkLabel)

            arrow("↑", label: DetailCopy.findPrevious) { model.findPrevious() }
            arrow("↓", label: DetailCopy.findNext) { model.findNext() }
        }
        .padding(RetainMetrics.findBarPadding)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    /// A field with something in it is drawn at the stronger border — the
    /// export's `#2f353c` — which is also what `RetainInteraction` uses for
    /// focus, so a field being typed into never loses it.
    private var fieldBorder: Color {
        model.findQuery.isEmpty ? RetainPalette.lineControlBorder : RetainInteraction.focusBorder
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
    let seek: () -> Void

    var body: some View {
        Button(action: seek) {
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
            // The rule hangs out into the pane's own padding, as the export
            // draws it, so the text under it stays on the same left edge as
            // every unmarked line.
            .padding(.leading, isMarked ? -RetainMetrics.transcriptMarkerRuleInset : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RetainSurfaceButtonStyle())
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
