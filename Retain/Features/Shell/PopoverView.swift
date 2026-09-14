import SwiftUI

// MARK: - What the popover can do

/// Everything the popover can ask for, in one value.
///
/// Closures rather than a reference to the controller: the cards are then views
/// over a snapshot and a set of verbs, which is what lets each of the five be
/// rendered without a status item, a panel or a microphone.
struct PopoverActions {
    var record: () -> Void = {}
    var pause: () -> Void = {}
    var resume: () -> Void = {}
    var requestStop: () -> Void = {}
    var finish: () -> Void = {}
    var annotate: (String) -> Void = { _ in }
    var openRecordingWindow: () -> Void = {}
    var dismiss: () -> Void = {}
}

// MARK: - The popover

/// Board 02: one card, 470 wide, in whichever of the five states the lecture is
/// in.
struct PopoverView: View {

    let snapshot: PopoverSnapshot
    let courses: CourseSelection
    let actions: PopoverActions

    var body: some View {
        card
            .frame(width: RetainMetrics.popoverWidth)
            .background(RetainPalette.surfaceWindow)
            .clipShape(RoundedRectangle(cornerRadius: RetainMetrics.radiusPopover))
            .overlay(
                RoundedRectangle(cornerRadius: RetainMetrics.radiusPopover)
                    .strokeBorder(RetainPalette.lineWindowBorder, lineWidth: 1)
            )
            .shadow(
                color: RetainMetrics.popoverShadow.color,
                radius: RetainMetrics.popoverShadow.radius,
                y: RetainMetrics.popoverShadow.offsetY
            )
            .padding(RetainMetrics.popoverShadow.extent)
    }

    @ViewBuilder
    private var card: some View {
        switch snapshot.state {
        case .ready:
            PopoverReadyCard(snapshot: snapshot, courses: courses, actions: actions)
        case .running:
            PopoverRunningCard(snapshot: snapshot, actions: actions)
        case .stopConfirmation:
            PopoverStopConfirmationCard(snapshot: snapshot, actions: actions)
        case .paused:
            PopoverPausedCard(snapshot: snapshot, actions: actions)
        case .summarizing:
            PopoverSummarizingCard(snapshot: snapshot, actions: actions)
        }
    }
}

// MARK: - Ready

/// Nothing is recording: pick a course and start.
struct PopoverReadyCard: View {

    let snapshot: PopoverSnapshot
    let courses: CourseSelection
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                RetainLabel(text: String(localized: "Ready", comment: "Popover header when nothing is recording"))

                HStack(spacing: RetainMetrics.popoverReadyRowGap) {
                    CoursePicker(courses: courses)

                    Button(action: actions.record) {
                        Text(verbatim: String(localized: "Record", comment: "Button that starts a recording"))
                    }
                    .buttonStyle(
                        RetainPrimaryButtonStyle(
                            padding: RetainMetrics.popoverRecordButtonPadding,
                            cornerRadius: RetainMetrics.radiusButton,
                            // The export writes the window's own background on
                            // this one label where every other accent fill
                            // carries `#0b0f0d`. The HTML wins.
                            ink: RetainPalette.surfaceWindow
                        )
                    )
                    .disabled(!snapshot.canRecord)
                }
                .padding(.top, RetainMetrics.popoverReadyRowTopGap)
            }
            .padding(RetainMetrics.popoverHeaderReady)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RetainPalette.surfaceMetaStrip)
            .overlay(alignment: .bottom) { RetainDivider() }

            HStack(spacing: RetainMetrics.popoverReadyFooterGap) {
                RetainLevelMeter(
                    level: nil,
                    barCount: RetainMetrics.meterBarCountReady,
                    height: RetainMetrics.waveformHeightReady,
                    appearance: .idle
                )

                Text(verbatim: PopoverReadyCard.silenceLine(input: snapshot.inputName))
                    .retainStyle(RetainTypography.captionSmall)
                    .foregroundStyle(RetainPalette.inkLabel)
            }
            .padding(RetainMetrics.popoverReadyFooter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Silence · MacBook Pro Microphone". Nothing is being recorded in this
    /// state, so the meter is flat and the word is always "Silence" — the
    /// export draws exactly that, and a live meter here would be a second
    /// microphone opened for a label.
    static func silenceLine(input: String) -> String {
        String(
            localized: "Silence · \(input)",
            comment: "The level line in the popover's ready state, with the microphone's name"
        )
    }
}

// MARK: - Running

/// A lecture is running: the timer, the meter, the last three transcript lines
/// and the annotation bar.
struct PopoverRunningCard: View {

    let snapshot: PopoverSnapshot
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            transcript
            PopoverAnnotationBar(submit: actions.annotate)
                .padding(RetainMetrics.popoverTranscriptBody)
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: RetainMetrics.popoverStatusRowGap) {
                RetainStatusDot(
                    colour: RetainPalette.redRecording,
                    diameter: RetainMetrics.statusDotPopover,
                    loop: .recordingPulse
                )
                RetainLabel(
                    text: String(localized: "Recording", comment: "Popover header while a lecture is being recorded, and the title of the recording window"),
                    ink: RetainPalette.redInk
                )
                Spacer(minLength: 0)
                if let watts = snapshot.watts {
                    Text(verbatim: PopoverRunningCard.wattage(watts))
                        .retainStyle(RetainTypography.captionSmall)
                        .foregroundStyle(RetainPalette.inkLabel)
                }
            }

            HStack(alignment: .bottom, spacing: 0) {
                PopoverTitleBlock(courseName: snapshot.courseName, noteBlocks: snapshot.noteBlocks)
                Spacer(minLength: 0)
                Text(verbatim: RetainTimeFormat.clock(snapshot.duration))
                    .retainStyle(RetainTypography.timerLarge)
                    .foregroundStyle(RetainPalette.inkPrimary)
            }
            .padding(.top, RetainMetrics.popoverTitleGapRunning)

            HStack(spacing: RetainMetrics.popoverMeterRowGap) {
                RetainLevelMeter(
                    level: snapshot.level,
                    barCount: RetainMetrics.meterBarCountPopover,
                    height: RetainMetrics.waveformHeightPopover,
                    appearance: .live
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: actions.pause) {
                    HStack(spacing: RetainMetrics.popoverPauseButtonGap) {
                        RetainPauseGlyph(size: RetainMetrics.pauseGlyphSmall, colour: RetainPalette.onAccent)
                        Text(verbatim: String(localized: "Pause", comment: "Button that holds a running recording"))
                    }
                }
                .buttonStyle(
                    RetainPrimaryButtonStyle(
                        textStyle: RetainTypography.buttonPanelFooter,
                        padding: RetainMetrics.popoverPauseButtonPadding,
                        cornerRadius: RetainMetrics.radiusButton
                    )
                )

                Button(action: actions.requestStop) {
                    Text(verbatim: String(localized: "Stop", comment: "Button that asks to end a recording"))
                }
                .buttonStyle(
                    RetainSecondaryButtonStyle(
                        textStyle: RetainTypography.buttonPanelFooter,
                        padding: RetainMetrics.popoverStopButtonPadding,
                        cornerRadius: RetainMetrics.radiusButton,
                        ink: RetainPalette.redInkBright,
                        border: RetainPalette.redBorderSwatch
                    )
                )
            }
            .padding(.top, RetainMetrics.popoverMeterGap)
        }
        .padding(RetainMetrics.popoverHeaderRunning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RetainPalette.surfaceMetaStrip)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                RetainLabel(text: String(localized: "Live transcript", comment: "Header of the popover's transcript section"))
                Spacer(minLength: 0)
                if let speaker = snapshot.lines.last?.speaker {
                    Text(verbatim: TranscriptLineRow.speakerName(speaker))
                        .retainStyle(RetainTypography.railHeaderNote)
                        .foregroundStyle(RetainPalette.inkLabel)
                }
            }
            .padding(RetainMetrics.popoverTranscriptHeader)

            VStack(alignment: .leading, spacing: RetainMetrics.transcriptPopoverLineGap) {
                ForEach(
                    TranscriptLadder.visible(snapshot.lines, opacities: RetainMetrics.transcriptPopoverOpacities),
                    id: \.line.id
                ) { rung in
                    TranscriptLineRow(
                        line: rung.line,
                        bodyStyle: RetainTypography.transcriptLinePopover,
                        isNewest: rung.line.id == snapshot.lines.last?.id
                    )
                    .opacity(rung.opacity)
                }
            }
            .padding(RetainMetrics.popoverTranscriptBody)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        Button(action: actions.openRecordingWindow) {
            HStack(spacing: 0) {
                Text(verbatim: String(localized: "Open summary", comment: "Opens the window showing the notes as they are written"))
                    .retainStyle(RetainTypography.popoverFooterAction)
                    .foregroundStyle(RetainPalette.inkPrimary)
                Spacer(minLength: 0)
                Text(verbatim: "↗")
                    .retainStyle(RetainTypography.captionSmall)
                    .foregroundStyle(RetainPalette.inkLabel)
            }
            .padding(RetainMetrics.popoverFooterPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { RetainDivider() }
    }

    // MARK: Copy

    /// "8.6 W" — one decimal, in the reader's own number format.
    static func wattage(_ watts: Double) -> String {
        String(
            localized: "\(watts.formatted(.number.precision(.fractionLength(1)))) W",
            comment: "The live power reading beside a running recording, in watts"
        )
    }
}

// MARK: - Shared chrome

/// The course and the line under it, which the running and paused cards share.
struct PopoverTitleBlock: View {

    let courseName: String
    let noteBlocks: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: courseName)
                .retainStyle(RetainTypography.popoverTitleRunning)
                .foregroundStyle(RetainPalette.inkPrimary)
            Text(verbatim: PopoverTitleBlock.subtitle(noteBlocks: noteBlocks))
                .retainStyle(RetainTypography.popoverSubtitle)
                .foregroundStyle(RetainPalette.inkLabel)
                .padding(.top, RetainMetrics.popoverSubtitleGap)
        }
    }

    /// The line under the title. The topic is not there yet — the model reads
    /// it out of the finished transcript — so what a running lecture can say
    /// about itself is how many cards it has written.
    static func subtitle(noteBlocks: Int) -> String {
        String(
            localized: "\(noteBlocks) note blocks",
            comment: "How many note cards a running lecture has produced"
        )
    }
}

/// A one-pixel rule in the divider colour. The export's `border-bottom`.
