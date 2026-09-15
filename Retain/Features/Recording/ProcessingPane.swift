import SwiftUI

/// What the window shows between the lecture ending and the notes existing.
///
/// Three things happen there and each of them takes real time: the recording is
/// transcribed again from the file, the speakers are separated, and the model
/// reads the whole hour and writes the notes. Before this, all three happened
/// behind a window that still drew a running lecture — which is why pressing
/// Finish looked like it did nothing.
///
/// It says which of the three is running and how far it has got. The last one
/// reports no fraction because the model does not stream a percentage; it gets
/// the moving dots instead, which is the honest picture of "working, and I
/// cannot tell you how much longer".
struct ProcessingPane: View {

    let phase: LectureSession.Phase

    /// The lecture's own name, so the screen says what it is working on rather
    /// than working in the abstract.
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.processingGap) {
            Text(verbatim: ProcessingCopy.heading)
                .retainStyle(RetainTypography.dialogTitle)
                .foregroundStyle(RetainPalette.inkPrimary)

            Text(verbatim: title)
                .retainStyle(RetainTypography.dialogBody)
                .foregroundStyle(RetainPalette.inkLabel)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: RetainMetrics.processingStepGap) {
                ForEach(ProcessingStep.allCases, id: \.self) { step in
                    row(step)
                }
            }
            .padding(.top, RetainMetrics.processingGap)
        }
        .frame(maxWidth: RetainMetrics.processingColumn, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - One step

    private func row(_ step: ProcessingStep) -> some View {
        let state = step.state(in: phase)

        return VStack(alignment: .leading, spacing: RetainMetrics.processingBarGap) {
            HStack(alignment: .firstTextBaseline, spacing: RetainMetrics.processingRowGap) {
                marker(for: state)
                    .frame(width: RetainMetrics.processingMarkerColumn, alignment: .leading)

                Text(verbatim: step.title)
                    .retainStyle(RetainTypography.fieldText)
                    .foregroundStyle(ink(for: state))

                Spacer(minLength: 0)

                if case .running(let fraction) = state, let fraction {
                    Text(verbatim: ProcessingCopy.percent(fraction))
                        .retainStyle(RetainTypography.captionSmall)
                        .foregroundStyle(RetainPalette.inkLabel)
                        .monospacedDigit()
                }
            }

            // A bar only where there is a real fraction behind it. The model
            // writing the notes reports none, and a bar that moves on a guess
            // is a lie the eye believes — that step keeps its moving dots and
            // nothing else.
            if case .running(let fraction) = state, let fraction {
                bar(fraction)
            }
        }
    }

    /// The progress of one pass, as the export draws a progress bar: a track
    /// and a fill, at the speech-model download's own height and radius.
    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width * max(0, min(1, fraction))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(RetainPalette.surfaceInsetControl)

                Capsule()
                    .fill(RetainPalette.accent)
                    .frame(width: width)
            }
        }
        .frame(height: RetainMetrics.processingBarHeight)
        .padding(.leading, RetainMetrics.processingMarkerColumn + RetainMetrics.processingRowGap)
    }

    @ViewBuilder
    private func marker(for state: ProcessingStep.State) -> some View {
        switch state {
        case .waiting:
            RetainStatusDot(colour: RetainPalette.inkDisabled, diameter: RetainMetrics.statusDotSmall)
        case .running:
            // The dots move. A screen that says "working" without moving is a
            // screen nobody believes.
            TypingIndicator()
        case .finished:
            RetainStatusDot(colour: RetainPalette.accent, diameter: RetainMetrics.statusDotSmall)
        }
    }

    private func ink(for state: ProcessingStep.State) -> Color {
        switch state {
        case .waiting: RetainPalette.inkDisabled
        case .running: RetainPalette.inkPrimary
        case .finished: RetainPalette.inkBody
        }
    }
}

// MARK: - The three steps

/// The passes a finished recording goes through, in order.
nonisolated enum ProcessingStep: CaseIterable, Hashable, Sendable {
    case transcribing
    case separatingSpeakers
    case writingNotes

    enum State: Hashable, Sendable {
        case waiting
        /// `nil` where the pass reports no fraction — the model writing the
        /// notes does not, and pretending otherwise would be a bar that moves
        /// on a guess.
        case running(Double?)
        case finished
    }

    var title: String {
        switch self {
        case .transcribing: ProcessingCopy.transcribing
        case .separatingSpeakers: ProcessingCopy.separatingSpeakers
        case .writingNotes: ProcessingCopy.writingNotes
        }
    }

    func state(in phase: LectureSession.Phase) -> State {
        switch phase {
        case .idle, .recording, .preparingModels:
            return .waiting

        case .transcribing(let fraction):
            return self == .transcribing ? .running(fraction) : .waiting

        case .separatingSpeakers(let fraction):
            switch self {
            case .transcribing: return .finished
            case .separatingSpeakers: return .running(fraction)
            case .writingNotes: return .waiting
            }

        case .writingNotes:
            return self == .writingNotes ? .running(nil) : .finished

        case .done, .failed:
            return .finished
        }
    }
}

nonisolated enum ProcessingCopy {

    static var heading: String {
        String(localized: "Working through the recording",
               comment: "Heading of the screen shown between a lecture ending and its notes existing")
    }

    static var transcribing: String {
        String(localized: "Writing the transcript",
               comment: "Processing step: the batch transcription pass")
    }

    static var separatingSpeakers: String {
        String(localized: "Separating the speakers",
               comment: "Processing step: diarization")
    }

    static var writingNotes: String {
        String(localized: "Writing the notes",
               comment: "Processing step: the model reading the whole transcript")
    }

    static func percent(_ fraction: Double) -> String {
        let clamped = max(0, min(1, fraction))
        return String(
            localized: "\(Int((clamped * 100).rounded())) %",
            comment: "A percentage on the processing screen"
        )
    }
}

// MARK: - And afterwards

/// The last thing the recording window says.
///
/// The lecture is opened in its own window the moment everything has run — see
/// `RecordingRoot` — so this is on screen for a moment and then behind that
/// window. It exists so the recording window never ends on a screen that is
/// still claiming to work.
struct FinishedPane: View {

    let phase: LectureSession.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.processingGap) {
            HStack(spacing: RetainMetrics.processingRowGap) {
                RetainStatusDot(
                    colour: phase.isFailure ? RetainPalette.redError : RetainPalette.accent,
                    diameter: RetainMetrics.statusDotSmall
                )

                Text(verbatim: phase.isFailure ? FinishedCopy.failed : FinishedCopy.done)
                    .retainStyle(RetainTypography.dialogTitle)
                    .foregroundStyle(RetainPalette.inkPrimary)
            }

            if case .failed(let reason) = phase {
                Text(verbatim: reason)
                    .retainStyle(RetainTypography.dialogBody)
                    .foregroundStyle(RetainPalette.redInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: FinishedCopy.where)
                    .retainStyle(RetainTypography.dialogBody)
                    .foregroundStyle(RetainPalette.inkLabel)
            }
        }
        .frame(maxWidth: RetainMetrics.processingColumn, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

nonisolated enum FinishedCopy {

    static var done: String {
        String(localized: "Finished", comment: "Recording window once every pass has run")
    }

    static var failed: String {
        String(localized: "Something did not run", comment: "Recording window when a pass failed")
    }

    static var `where`: String {
        String(localized: "The lecture is open in its own window, and in the library.",
               comment: "Recording window saying where the finished lecture is")
    }
}
