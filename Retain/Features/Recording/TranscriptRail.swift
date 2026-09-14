import SwiftUI

/// The right-hand rail of board 01: the last five transcript lines, faded by
/// age, with the two buttons that end the lecture under them.
struct TranscriptRail: View {

    let shell: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                TranscriptRailLines(lines: lines)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .frame(maxHeight: .infinity)
        .background(RetainPalette.surfaceRail)
        .overlay(alignment: .leading) { RetainVerticalDivider() }
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

    private var footer: some View {
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
