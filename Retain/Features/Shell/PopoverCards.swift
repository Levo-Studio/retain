import SwiftUI

// MARK: - The course picker

/// The field board 02 draws in the ready state, and the list behind it the
/// board does not draw.
///
/// A menu rather than a sheet or a second card: the popover is already a
/// transient window, and a course is picked in one click far more often than it
/// is created. Creating one is board 07's dialog and belongs to the library.
struct CoursePicker: View {

    let courses: CourseSelection

    var body: some View {
        // Bound by id rather than by `Course`: the selection can be nothing at
        // all — a term with no courses in it — and a binding to an optional
        // course would put "no course" in the menu as something to pick.
        RetainPickerField(
            selection: Binding(
                get: { courses.selected?.id },
                set: { id in
                    if let course = courses.courses.first(where: { $0.id == id }) {
                        courses.select(course)
                    }
                }
            ),
            options: courses.courses.map(\.id),
            title: { id in courses.courses.first { $0.id == id }?.name ?? "" },
            cornerRadius: RetainMetrics.radiusReadyStateField
        ) {
            Text(verbatim: name)
                .retainStyle(RetainTypography.fieldText)
                .foregroundStyle(courses.selected == nil ? RetainPalette.inkLabel : RetainPalette.inkPrimary)
        }
        .disabled(courses.courses.isEmpty)
    }

    /// With no courses in the current term there is nothing to record into, so
    /// the field says so instead of standing empty. The Record button beside it
    /// is unavailable for the same reason.
    private var name: String {
        courses.selected?.name
            ?? String(localized: "No course", comment: "The course field when the current term has no courses")
    }
}

// MARK: - The annotation bar

/// `⌘⇧M` in the popover: a line that goes to the model with the block it falls
/// in.
struct PopoverAnnotationBar: View {

    let submit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: RetainMetrics.annotationBarPopoverGap) {
            Rectangle()
                .fill(RetainPalette.blue)
                .frame(
                    width: RetainMetrics.annotationRulePopover.width,
                    height: RetainMetrics.annotationRulePopover.height
                )

            TextField(
                "",
                text: $text,
                prompt: Text(verbatim: RetainAnnotationCopy.placeholder)
                    .foregroundStyle(RetainPalette.inkLabel)
            )
            .textFieldStyle(.plain)
            .focused($isFocused)
            .retainStyle(RetainTypography.captionLarge)
            .foregroundStyle(RetainPalette.inkBodyStrong)
            .onSubmit(send)

            Text(verbatim: "⏎")
                .retainStyle(RetainTypography.enterHint)
                .foregroundStyle(RetainPalette.inkLabel)
        }
        .retainFieldChrome(
            isFocused: isFocused,
            cornerRadius: RetainMetrics.radiusPopoverAnnotationBar,
            padding: RetainMetrics.annotationBarPopoverPadding
        )
    }

    private func send() {
        submit(text)
        text = ""
    }
}

/// The one sentence the annotation composer shows in both places it appears.
nonisolated enum RetainAnnotationCopy {
    static var placeholder: String {
        String(
            localized: "Note — goes to the model",
            comment: "Placeholder of the annotation composer, which sends what is typed to the language model"
        )
    }
}

// MARK: - Stop confirmation

/// What "Stop" asks before it ends a lecture.
struct PopoverStopConfirmationCard: View {

    let snapshot: PopoverSnapshot
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RetainLabel(text: Self.runningFor(snapshot.duration))

            Text(verbatim: snapshot.courseName)
                .retainStyle(RetainTypography.popoverTitleReady)
                .foregroundStyle(RetainPalette.inkPrimary)
                .padding(.top, RetainMetrics.popoverTitleGapStopConfirmation)

            Text(verbatim: Self.explanation)
                .retainStyle(RetainTypography.popoverBody)
                .foregroundStyle(RetainPalette.inkLabel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, RetainMetrics.popoverBodyGapStopConfirmation)

            HStack(spacing: RetainMetrics.popoverButtonRowGap) {
                Button(action: actions.pause) {
                    HStack(spacing: RetainMetrics.popoverLargeButtonGap) {
                        RetainPauseGlyph(size: RetainMetrics.pauseGlyphLarge, colour: RetainPalette.onAccent)
                        Text(verbatim: String(localized: "Pause", comment: "Button that holds a running recording"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    RetainPrimaryButtonStyle(
                        textStyle: RetainTypography.buttonPopoverLarge,
                        padding: RetainMetrics.popoverLargeButtonPadding,
                        cornerRadius: RetainMetrics.radiusPopoverPrimaryButton
                    )
                )

                Button(action: actions.finish) {
                    Text(verbatim: String(localized: "Finish", comment: "Button that ends a recording and starts the summary"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    RetainSecondaryButtonStyle(
                        textStyle: RetainTypography.buttonPopoverLarge,
                        padding: RetainMetrics.popoverLargeButtonPadding,
                        cornerRadius: RetainMetrics.radiusPopoverPrimaryButton,
                        ink: RetainPalette.redInkBright,
                        border: RetainPalette.redBorderSwatch
                    )
                )
            }
            .padding(.top, RetainMetrics.popoverButtonRowGapStopConfirmation)
        }
        .padding(RetainMetrics.popoverHeaderStopConfirmation)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func runningFor(_ duration: TimeInterval) -> String {
        String(
            localized: "Recording for \(ElapsedTime.wholeMinutes(duration)) minutes",
            comment: "Label above the stop confirmation, saying how long the recording has run"
        )
    }

    /// **Not in the README's copy table.** The table translates the labels and
    /// stops at the sentences; this one is translated from the export's
    /// "Pausieren hält sofort an und läuft danach weiter. Beenden schließt ab
    /// und startet die Zusammenfassung."
    static var explanation: String {
        String(
            localized: "Pause holds immediately and carries on afterwards. Finish closes the recording and starts the summary.",
            comment: "The sentence in the stop confirmation explaining what the two buttons do"
        )
    }
}

// MARK: - Paused

/// The microphone is closed and the lecture is not over.
struct PopoverPausedCard: View {

    let snapshot: PopoverSnapshot
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            lastLine
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: RetainMetrics.popoverStatusRowGap) {
                RetainPauseGlyph(size: RetainMetrics.pauseGlyphSmall, colour: RetainPalette.inkDim)
                RetainLabel(text: String(localized: "Paused", comment: "Popover header while a recording is paused"))
            }

            HStack(alignment: .bottom, spacing: 0) {
                PopoverTitleBlock(courseName: snapshot.courseName, noteBlocks: snapshot.noteBlocks)
                Spacer(minLength: 0)
                Text(verbatim: ElapsedTime.clock(snapshot.duration))
                    .retainStyle(RetainTypography.timerLarge)
                    .foregroundStyle(RetainPalette.inkDim)
            }
            .padding(.top, RetainMetrics.popoverTitleGapPaused)

            HStack(spacing: RetainMetrics.popoverMeterRowGap) {
                RetainLevelMeter(
                    level: nil,
                    barCount: RetainMetrics.meterBarCountPopover,
                    height: RetainMetrics.waveformHeightPopover,
                    appearance: .paused
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: actions.resume) {
                    Text(verbatim: String(localized: "Resume", comment: "Button that continues a paused recording"))
                }
                .buttonStyle(
                    RetainPrimaryButtonStyle(
                        textStyle: RetainTypography.buttonPanelFooter,
                        padding: RetainMetrics.popoverResumeButtonPadding,
                        cornerRadius: RetainMetrics.radiusButton
                    )
                )
            }
            .padding(.top, RetainMetrics.popoverMeterGap)
        }
        .padding(RetainMetrics.popoverHeaderPaused)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RetainPalette.surfaceMetaStrip)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    @ViewBuilder
    private var lastLine: some View {
        if let line = snapshot.lines.last {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    RetainLabel(
                        text: String(
                            localized: "Last line before the pause",
                            comment: "Header above the transcript line a paused recording stopped on"
                        )
                    )
                    Spacer(minLength: 0)
                    Text(verbatim: ElapsedTime.clock(line.start))
                        .retainStyle(RetainTypography.railHeaderNote)
                        .foregroundStyle(RetainPalette.inkLabel)
                }
                .padding(RetainMetrics.popoverLastLineHeader)

                Text(verbatim: line.text)
                    .retainStyle(RetainTypography.transcriptLinePopover)
                    .foregroundStyle(RetainPalette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(RetainMetrics.popoverLastLineBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: actions.finish) {
                Text(verbatim: String(localized: "Finish", comment: "Button that ends a recording and starts the summary"))
                    .retainStyle(RetainTypography.popoverFooterAction)
                    .foregroundStyle(RetainPalette.redInkBright)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text(verbatim: String(localized: "⌘⇧P resumes", comment: "Reminder of the shortcut that resumes a paused recording"))
                .retainStyle(RetainTypography.captionSmall)
                .foregroundStyle(RetainPalette.inkLabel)
        }
        .padding(RetainMetrics.popoverFooterPaddingPaused)
        .overlay(alignment: .top) { RetainDivider() }
    }
}

// MARK: - Summarizing

/// The passes that run after the microphone closes.
struct PopoverSummarizingCard: View {

    let snapshot: PopoverSnapshot
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            card
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: RetainMetrics.popoverStatusRowGap) {
                RetainStatusDot(
                    colour: RetainPalette.amber,
                    diameter: RetainMetrics.statusDotPopover,
                    breathes: true
                )
                RetainLabel(
                    text: String(localized: "Summarizing", comment: "Popover header while the passes after a recording run"),
                    ink: RetainPalette.amberInk
                )
            }

            Text(verbatim: snapshot.courseName)
                .retainStyle(RetainTypography.popoverTitleSummarizing)
                .foregroundStyle(RetainPalette.inkPrimary)
                .padding(.top, RetainMetrics.popoverTitleGapSummarizing)

            Text(verbatim: Self.subtitle(duration: snapshot.duration, noteBlocks: snapshot.noteBlocks))
                .retainStyle(RetainTypography.popoverSubtitle)
                .foregroundStyle(RetainPalette.inkLabel)
                .padding(.top, RetainMetrics.popoverSubtitleGapSummarizing)

            SweepProgressBar(fraction: snapshot.progress)
                .padding(.top, RetainMetrics.popoverMeterGap)
        }
        .padding(RetainMetrics.popoverHeaderSummarizing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RetainPalette.surfaceMetaStrip)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Button(action: actions.openRecordingWindow) {
                HStack(spacing: RetainMetrics.popoverCardGap) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: String(localized: "Open summary", comment: "Opens the window showing the notes as they are written"))
                            .retainStyle(RetainTypography.popoverCardTitle)
                            .foregroundStyle(RetainPalette.onAccent)
                        Text(verbatim: Self.cardSubtitle(markers: snapshot.markers, sections: snapshot.noteBlocks))
                            .retainStyle(RetainTypography.popoverCardSubtitle)
                            .foregroundStyle(RetainPalette.onAccentSecondary)
                            .padding(.top, RetainMetrics.popoverCardSubtitleGap)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: "↗")
                        .retainStyle(RetainTypography.popoverCardTitle)
                        .foregroundStyle(RetainPalette.onAccent)
                }
                .padding(RetainMetrics.popoverCardPadding)
                .background(
                    RetainPalette.accent,
                    in: RoundedRectangle(cornerRadius: RetainMetrics.radiusOpenSummaryCard)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: actions.dismiss) {
                Text(verbatim: String(localized: "keep running in the background", comment: "Dismisses the popover and leaves the summary running"))
                    .retainStyle(RetainTypography.popoverFooterAction)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, RetainMetrics.popoverBackgroundActionGap)
        }
        .padding(RetainMetrics.popoverSummarizingBody)
    }

    // MARK: Copy

    /// **The export's third clause has no source.** Board 02 reads "47 min
    /// aufgenommen · Block 3 von 4 · noch etwa 20 s", and nothing in Retain can
    /// say how long a model will take — LM Studio reports tokens after the fact
    /// and not an estimate before it. The two clauses that are knowable are
    /// shown and the estimate is left out.
    static func subtitle(duration: TimeInterval, noteBlocks: Int) -> String {
        String(
            localized: "\(ElapsedTime.wholeMinutes(duration)) min recorded · \(noteBlocks) note blocks",
            comment: "The line under the title while a recording is being summarised"
        )
    }

    static func cardSubtitle(markers: Int, sections: Int) -> String {
        String(
            localized: "\(markers) markers · \(sections) sections",
            comment: "What the finished summary contains, under the Open summary card"
        )
    }
}

// MARK: - The sweep

/// `sweep` — a bar 30 % wide travelling across a track that never says how far
/// along the work is.
///
/// Under Reduce Motion the same track is filled to the fraction that *is*
/// known, standing still, which is what the design README asks for.
struct SweepProgressBar: View {

    let fraction: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var atEnd = false

    var body: some View {
        Group {
            if travels {
                GeometryReader { geometry in
                    let barWidth = geometry.size.width * RetainMotion.sweep.barWidthFraction

                    RoundedRectangle(cornerRadius: RetainMetrics.radiusProgressBar)
                        .fill(RetainPalette.amber)
                        .frame(width: barWidth)
                        .offset(x: barWidth * offsetFraction)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(RetainMotion.animation(.sweep, reduceMotion: reduceMotion), value: atEnd)
                        .onAppear { atEnd = true }
                }
                .frame(height: RetainMetrics.progressBarHeightSummarizing)
                .background(
                    RetainPalette.lineWindowBorder,
                    in: RoundedRectangle(cornerRadius: RetainMetrics.radiusProgressBar)
                )
                .clipShape(RoundedRectangle(cornerRadius: RetainMetrics.radiusProgressBar))
            } else {
                // Reduce Motion turns the indeterminate bar into the ordinary
                // determinate one, which is the same track every other progress
                // bar in Retain is drawn in.
                RetainProgressTrack(
                    fraction: fraction,
                    height: RetainMetrics.progressBarHeightSummarizing,
                    fill: RetainPalette.amber
                )
            }
        }
    }

    private var travels: Bool { RetainMotion.showsTravellingSweep(reduceMotion: reduceMotion) }

    /// CSS translates the bar by multiples of its own width, `-100 %` to
    /// `320 %`.
    private var offsetFraction: CGFloat {
        atEnd ? RetainMotion.sweep.toFraction : RetainMotion.sweep.fromFraction
    }
}
