import SwiftUI

/// The right-hand rail of board 01: the last five transcript lines, faded by
/// age, with the two buttons that end the lecture under them.
struct TranscriptRail: View {

    let shell: ShellModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { scroll in
                ScrollView {
                    TranscriptRailLines(lines: lines)
                        // An anchor at the very end rather than the last line's
                        // own id: the newest line is replaced as it is spoken —
                        // the partial becomes a line and a new partial takes
                        // its place — so scrolling to it by id chases a moving
                        // target.
                        .overlay(alignment: .bottom) {
                            Color.clear.frame(height: 1).id(Self.endID)
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: lines.count) { follow(scroll) }
                .onChange(of: shell.session.partial) { follow(scroll) }
                .task { follow(scroll) }
            }

            footer
        }
        .frame(maxHeight: .infinity)
        .background(RetainPalette.surfaceRail)
        .overlay(alignment: .leading) { RetainVerticalDivider() }
    }

    private static let endID = "transcript-end"

    /// Keeps the newest line in view while the lecture runs.
    ///
    /// The whole transcript is in the rail now, so without this a lecture
    /// scrolls its own newest words off the bottom within a minute. Scrolling
    /// back by hand still works — this only fires when a line arrives.
    private func follow(_ scroll: ScrollViewProxy) {
        withAnimation(RetainMotion.reveal(reduceMotion: reduceMotion)) {
            scroll.scrollTo(Self.endID, anchor: .bottom)
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            RetainLabel(text: String(localized: "Transcript", comment: "Header of the recording window's transcript rail"))
            Spacer(minLength: 0)
            Text(verbatim: String(localized: "live", comment: "Note in the transcript rail header saying the transcript is running"))
                .retainStyle(RetainTypography.railHeaderNote)
                .foregroundStyle(RetainPalette.inkFaint)
        }
        .padding(RetainMetrics.railHeaderRecording)
    }

    /// The rail's footer, which is **not** two buttons once the lecture has
    /// stopped.
    ///
    /// It was two buttons regardless of what the session was doing, so pressing
    /// Finish changed nothing on screen: the same Pause and Finish, the same
    /// running clock above them, while the writer closed and the batch pass ran
    /// for minutes. Reported, correctly, as the Finish button not working.
    @ViewBuilder
    private var footer: some View {
        switch shell.session.phase {
        case .transcribing, .separatingSpeakers, .preparingModels:
            working
        case .done, .failed:
            finished
        case .idle, .recording:
            running
        }
    }

    /// What the footer says while the passes over the finished recording run.
    private var working: some View {
        HStack(spacing: RetainMetrics.panelFooterButtonGap) {
            TypingIndicator()

            Text(verbatim: RecordingRailCopy.line(for: shell.session.phase))
                .retainStyle(RetainTypography.buttonPanelFooter)
                .foregroundStyle(RetainPalette.inkLabel)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(RetainMetrics.railFooterPadding)
        .overlay(alignment: .top) { RetainDivider(colour: RetainPalette.lineControlBorder) }
    }

    /// And afterwards. The window stays open — the transcript is worth reading
    /// — but there is nothing left to stop.
    private var finished: some View {
        HStack(spacing: RetainMetrics.panelFooterButtonGap) {
            Text(verbatim: RecordingRailCopy.line(for: shell.session.phase))
                .retainStyle(RetainTypography.buttonPanelFooter)
                .foregroundStyle(
                    shell.session.phase.isFailure ? RetainPalette.redInk : RetainPalette.inkLabel
                )
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(RetainMetrics.railFooterPadding)
        .overlay(alignment: .top) { RetainDivider(colour: RetainPalette.lineControlBorder) }
    }

    private var running: some View {
        HStack(spacing: RetainMetrics.panelFooterButtonGap) {
            Button(action: holdOrContinue) {
                Text(verbatim: holdOrContinueLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                RetainSecondaryButtonStyle(
                    textStyle: RetainTypography.buttonPanelFooter,
                    padding: RetainMetrics.panelFooterButtonPadding,
                    cornerRadius: RetainMetrics.radiusButton,
                    // The rail's Pause is the one secondary button the export
                    // draws at the emphasised border rather than the plain one.
                    border: RetainPalette.controlBorderEmphasisedSwatch
                )
            )

            Button(action: shell.finish) {
                Text(verbatim: String(localized: "Finish", comment: "Button that ends a recording and starts the summary"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                RetainSecondaryButtonStyle(
                    textStyle: RetainTypography.buttonPanelFooter,
                    padding: RetainMetrics.panelFooterButtonPadding,
                    cornerRadius: RetainMetrics.radiusButton,
                    ink: RetainPalette.redInk,
                    border: RetainPalette.redBorderSwatch
                )
            )
        }
        .padding(RetainMetrics.railFooterPadding)
        .overlay(alignment: .top) { RetainDivider(colour: RetainPalette.lineControlBorder) }
    }

    /// The left button is the same button in both of its states: the export
    /// draws "Pause", and a paused recording has to be able to go on.
    private func holdOrContinue() {
        if shell.session.isPaused {
            shell.resume()
        } else {
            shell.pause()
        }
    }

    private var holdOrContinueLabel: String {
        shell.session.isPaused
            ? String(localized: "Resume", comment: "Button that continues a paused recording")
            : String(localized: "Pause", comment: "Button that holds a running recording")
    }

    /// The finished lines plus the one currently forming.
    ///
    /// The partial is a line like any other as far as the rail is concerned —
    /// it is the newest, so it is the one at full strength with the caret after
    /// it — and it is built here rather than kept in the session because it is
    /// not a line yet: it has no end and it will be replaced by one.
    private var lines: [TranscriptLine] {
        guard !shell.session.partial.isEmpty else { return shell.session.lines }
        return shell.session.lines + [
            TranscriptLine(
                id: Self.partialID,
                start: shell.session.lines.last?.end ?? 0,
                end: shell.session.recorder.duration,
                text: shell.session.partial,
                isProvisional: true
            )
        ]
    }

    /// One identity for the forming line, so a `ForEach` treats a growing
    /// partial as the same row rather than as a new one every few words.
    private static let partialID = UUID()
}

// MARK: - The lines themselves

/// The five lines and the ladder they are faded on.
///
/// Split out for the same reason `NotesList` is: a scroll view is not something
/// a still picture of this rail can be compared through.
struct TranscriptRailLines: View {

    let lines: [TranscriptLine]

    var body: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.transcriptRailLineGap) {
            ForEach(
                TranscriptLadder.visible(lines, opacities: RetainMetrics.transcriptRailOpacities),
                id: \.line.id
            ) { rung in
                TranscriptLineRow(
                    line: rung.line,
                    bodyStyle: RetainTypography.transcriptLineRail,
                    isNewest: rung.line.id == lines.last?.id
                )
                .opacity(rung.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RetainMetrics.railBodyRecording)
    }
}


// MARK: -

nonisolated enum RecordingRailCopy {

    /// One line saying what is happening to the recording now that it has
    /// stopped. The percentages come from the passes themselves.
    static func line(for phase: LectureSession.Phase) -> String {
        switch phase {
        case .preparingModels:
            String(localized: "Loading the speech models …",
                   comment: "Recording rail footer while the speech models are being fetched")
        case .transcribing(let fraction):
            String(localized: "Writing the transcript · \(percent(fraction)) %",
                   comment: "Recording rail footer during the batch transcription pass")
        case .separatingSpeakers(let fraction):
            String(localized: "Separating the speakers · \(percent(fraction)) %",
                   comment: "Recording rail footer during diarization")
        case .done:
            String(localized: "Finished. The notes are in the library.",
                   comment: "Recording rail footer once everything has run")
        case .failed(let reason):
            reason
        case .idle, .recording:
            ""
        }
    }

    private static func percent(_ fraction: Double) -> Int {
        Int((max(0, min(1, fraction)) * 100).rounded())
    }
}
