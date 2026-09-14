import SwiftUI

// MARK: - Where a note is drawn

/// The two places notes appear. They are not the same layout: the recording
/// screen numbers its blocks and indents the body past the number, and the
/// detail screen has no numbers and sets a wider measure.
nonisolated enum RetainNoteLayout: Sendable, Equatable, CaseIterable {
    case recording
    case detail
}

// MARK: - A user highlight's look

/// What a passage the user marked looks like.
///
/// **Not drawn anywhere in the export.** Board 03 draws the emphasised term and
/// board 04 draws a search hit; a highlight the user made by hand over their
/// own notes is neither, and no board has one on it. Rather than pick a colour
/// here, the renderer takes one — so the day the owner settles it, it is
/// settled in one place and not discovered in a diff.
nonisolated struct RetainNoteHighlightStyle: Sendable, Equatable {
    let background: Color
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
}

// MARK: - The renderer

/// One note block's Markdown, drawn as board 03 draws it.
///
/// Headings, paragraphs, bullet lists and an emphasised term — the four shapes
/// the model is allowed to write. Everything it lays out comes from
/// `RetainTypography` and `RetainMetrics`; there is no number in this file that
/// is not a structural zero.
struct RetainMarkdownView: View {

    let markdown: String

    var layout: RetainNoteLayout = .detail

    /// Character ranges into `RetainMarkdown.plainText(of:)`.
    var highlights: [Range<Int>] = []

    var highlightStyle: RetainNoteHighlightStyle?

    /// The block that is still being written is drawn dim, with its heading
    /// and paragraph in the dim ink — board 01, block 03.
    var isBeingWritten: Bool = false

    /// The blinking caret at the end of the last line of a block whose text is
    /// still arriving. Off everywhere but the recording screen, where board 01
    /// draws it inside the open block's paragraph.
    var showsTrailingCaret: Bool = false

    private var elements: [RetainNoteElement] {
        RetainMarkdown.elements(of: markdown, highlights: highlights)
    }

    var body: some View {
        if showsTrailingCaret {
            RetainCaretTimeline { opacity in
                blocks(caretOpacity: opacity)
            }
        } else {
            blocks(caretOpacity: nil)
        }
    }

    private func blocks(caretOpacity: Double?) -> some View {
        let elements = elements
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
                view(
                    for: element,
                    caretOpacity: index == elements.count - 1 ? caretOpacity : nil
                )
                .padding(.top, topGap(for: element, at: index))
            }
        }
    }

    // MARK: Elements

    @ViewBuilder
    private func view(for element: RetainNoteElement, caretOpacity: Double?) -> some View {
        switch element {
        case let .heading(runs):
            rendered(
                runs,
                style: RetainTypography.noteHeading,
                ink: headingInk,
                caretOpacity: caretOpacity
            )

        case let .paragraph(runs):
            rendered(runs, style: paragraphStyle, ink: paragraphInk, caretOpacity: caretOpacity)
                .frame(maxWidth: paragraphWidth, alignment: .leading)

        case let .bulletList(items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "•")
                            .retainStyle(bulletStyle)
                            .foregroundStyle(RetainPalette.inkMuted)
                            .frame(width: bulletIndent, alignment: .leading)
                        rendered(
                            item,
                            style: bulletStyle,
                            ink: RetainPalette.inkMuted,
                            caretOpacity: index == items.count - 1 ? caretOpacity : nil
                        )
                    }
                }
            }
            .frame(maxWidth: paragraphWidth, alignment: .leading)
        }
    }

    /// The runs of one line as a single `Text`, so it breaks, selects and reads
    /// as one piece of prose rather than as a row of separate labels.
    private func rendered(
        _ runs: [RetainInlineRun],
        style: RetainTextStyle,
        ink: Color,
        caretOpacity: Double?
    ) -> some View {
        let termStyle = RetainTextStyle(
            size: style.size,
            weight: RetainTypography.emphasisedTermWeight,
            lineHeight: style.lineHeight,
            tracking: style.tracking,
            uppercase: style.uppercase,
            monospacedDigits: style.monospacedDigits
        )

        var text = Text(verbatim: "")
        for run in runs {
            var piece = Text(verbatim: run.text)
            if run.isTerm {
                piece = piece
                    .font(termStyle.font)
                    .foregroundStyle(RetainPalette.inkPrimary)
                    .customAttribute(RetainTermMark())
            }
            if run.isHighlighted {
                piece = piece.customAttribute(RetainHighlightMark())
            }
            text = text + piece
        }

        return text
            .retainStyle(style)
            .foregroundStyle(ink)
            .textRenderer(
                RetainNoteTextRenderer(
                    termBackground: RetainPalette.termHighlight,
                    termRadius: RetainMetrics.radiusTermHighlight,
                    termPadding: RetainMetrics.termHighlightPadding.leading,
                    highlight: highlightStyle,
                    caret: caretOpacity.map(RetainCaretStyle.notes(opacity:))
                )
            )
    }

    // MARK: Spacing

    private func topGap(for element: RetainNoteElement, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }

        switch element {
        case .heading:
            return layout == .recording
                ? RetainMetrics.noteBlockGapRecording
                : RetainMetrics.noteBlockGapDetail
        case .paragraph:
            return layout == .recording
                ? RetainMetrics.noteParagraphGapRecording
                : RetainMetrics.noteParagraphGapDetail
        case .bulletList:
            return layout == .recording
                ? RetainMetrics.noteBulletGapRecording
                : RetainMetrics.noteBulletGapDetail
        }
    }

    private var paragraphStyle: RetainTextStyle {
        layout == .recording
            ? RetainTypography.noteParagraphRecording
            : RetainTypography.noteParagraphDetail
    }

    private var bulletStyle: RetainTextStyle {
        layout == .recording
            ? RetainTypography.noteBulletRecording
            : RetainTypography.noteBulletDetail
    }

    private var bulletIndent: CGFloat {
        layout == .recording
            ? RetainMetrics.noteBulletIndentRecording
            : RetainMetrics.noteBulletIndentDetail
    }

    /// `64ch` and `70ch` resolved against the paragraph's own zero, because a
    /// `ch` is a measure in the text's font and not a point value.
    private var paragraphWidth: CGFloat {
        let measure = layout == .recording
            ? RetainMetrics.noteParagraphWidthRecording
            : RetainMetrics.noteParagraphWidthDetail
        return RetainTypography.chWidth(of: paragraphStyle) * measure
    }

    private var headingInk: Color {
        isBeingWritten ? RetainPalette.inkDim : RetainPalette.inkPrimary
    }

    private var paragraphInk: Color {
        isBeingWritten ? RetainPalette.inkDim : RetainPalette.inkBody
    }
}

// MARK: - Marks the renderer paints behind

private struct RetainTermMark: TextAttribute {}

private struct RetainHighlightMark: TextAttribute {}

/// Paints the backgrounds a plain `Text` cannot.
///
/// `AttributedString`'s own background attribute has no corner radius and no
/// horizontal padding, and the export's term highlight has both — 3px and
/// `0 3px`. Drawing them in a `TextRenderer` keeps everything a `Text` is good
/// at (line breaking, selection, accessibility) and puts the two rounded rects
/// exactly where the glyph runs are.
///
/// A term and a user highlight over the same words are drawn as two layers, the
/// highlight on top, and the run keeps the term's weight and ink underneath —
/// so neither mark disappears because the other one is also there.
private struct RetainNoteTextRenderer: TextRenderer {

    let termBackground: Color
    let termRadius: CGFloat
    let termPadding: CGFloat
    let highlight: RetainNoteHighlightStyle?

    /// Set only on the last line of a block that is still being written.
    let caret: RetainCaretStyle?

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[RetainTermMark.self] != nil {
                    fill(run, inset: termPadding, radius: termRadius, colour: termBackground, in: &context)
                }
                if run[RetainHighlightMark.self] != nil, let highlight {
                    fill(
                        run,
                        inset: highlight.horizontalPadding,
                        radius: highlight.cornerRadius,
                        colour: highlight.background,
                        in: &context
                    )
                }
            }
        }

        for line in layout {
            for run in line {
                context.draw(run)
            }
        }

        if let caret, let bounds = layout.last?.last?.typographicBounds {
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

    private func fill(
        _ run: Text.Layout.Run,
        inset: CGFloat,
        radius: CGFloat,
        colour: Color,
        in context: inout GraphicsContext
    ) {
        let bounds = run.typographicBounds.rect.insetBy(dx: -inset, dy: 0)
        context.fill(Path(roundedRect: bounds, cornerRadius: radius), with: .color(colour))
    }
}
