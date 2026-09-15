import AppKit
import SwiftUI

// MARK: - Root

/// Board 01: the title bar, the meta strip, the notes on the left and the live
/// transcript on the right.
struct RecordingRoot: View {

    let shell: ShellModel

    /// Builds the detail model for the lecture that has just finished.
    ///
    /// Handed in by the window controller, which is the only object here with a
    /// database. `nil` in a preview and in the board snapshot, where there is
    /// no store at all.
    var makeDetail: ((Recording) -> RecordingDetailModel)?

    @State private var finished: RecordingDetailModel?

    /// **One window, three states, in the order a lecture goes through them.**
    ///
    /// While it runs there is the transcript and nothing else — no notes
    /// column, and nothing sent to the model. When it stops, the same window
    /// shows what is being done to the recording. When that is over it says so
    /// and hands the lecture to its own window, where the notes, the chapters
    /// and the transcript tab live.
    ///
    /// They swap instantly. Every one of them is drawn from something already
    /// in memory, and a fade on a local change is Retain adding a delay to
    /// something that is already there.
    var body: some View {
        Group {
            if let finished {
                // **The finished lecture alone.** It brings its own title bar,
                // its own meta strip and its own tabs, so keeping the recording
                // chrome above it drew two of each: two topics, two courses,
                // two model pills, and a clock still counting a lecture that
                // had stopped.
                RecordingDetailView(model: finished)
            } else {
                VStack(spacing: 0) {
                    RecordingTitleBar(shell: shell)

                    // The same row, on the same edge, with the same room as
                    // every other window — and as the finished lecture, which
                    // replaces this whole view the moment the notes exist. Its
                    // absence was a jump: the bar, the strip and the tabs all
                    // shifted down a row when a lecture ended.
                    RetainWindowTitle(
                        title: lectureName,
                        leading: RetainMetrics.metaStripCellFirst.leading
                    )

                    RecordingMetaStrip(session: shell.session, courses: shell.courses)

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(RetainPalette.surfaceWindow)
        .task { await shell.courses.follow() }
        .task(id: stage) {
            guard stage == .finished, finished == nil else { return }
            guard let recording = await shell.session.finishedRecording() else { return }
            let model = makeDetail?(recording)
            await model?.load()
            finished = model
        }
    }

    // MARK: -

    private enum Stage: Hashable { case recording, processing, finished }

    private var stage: Stage {
        switch shell.session.phase {
        case .idle, .recording, .preparingModels: .recording
        case .transcribing, .separatingSpeakers, .writingNotes: .processing
        case .done, .failed: .finished
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .recording:
            LiveTranscriptPane(shell: shell)

        case .processing:
            ProcessingPane(phase: shell.session.phase, title: lectureTitle)

        case .finished:
            // Only reached while the lecture is still being read back, or when
            // there is no store to read it from. Once it is loaded the window
            // shows it instead of this, chrome and all — see `body`.
            FinishedPane(phase: shell.session.phase)
        }
    }

    /// The course the lecture being processed was recorded into.
    ///
    /// From the session, not from the course picker. The picker is the window's
    /// current selection and it moves — open the library, click another course,
    /// and the screen processing your maths lesson starts claiming it is
    /// processing biology. The session holds the course the microphone was
    /// opened for, and follows it if the lecture is moved mid-recording.
    private var lectureTitle: String {
        shell.session.course?.name ?? ""
    }

    /// What the window is called while the lecture runs: the course and when it
    /// started, which is what the finished lecture's own row says.
    private var lectureName: String {
        let started = shell.session.startedAt.formatted(
            .dateTime.day().month(.wide).year().hour().minute()
        )
        guard let course = shell.session.course else { return started }
        return DetailCopy.joined(course.name, started)
    }
}

// MARK: - Title bar

/// 38 points tall, with the traffic lights on the left and the state of the
/// microphone on the right.
struct RecordingTitleBar: View {

    let shell: ShellModel

    private var session: LectureSession { shell.session }
    private var power: PowerDrawMonitor { shell.power }

    /// Broken out of `body`: the bar has enough in it that the type checker
    /// gives up on the whole thing as one expression.
    @ViewBuilder
    private var controls: some View {
        // A closure rather than a ternary over two method references: the
        // compiler fails to type-check the latter, and reports it as a bug in
        // itself rather than as a message anybody can act on.
        Button {
            if session.isPaused {
                shell.resume()
            } else {
                shell.pause()
            }
        } label: {
            Text(verbatim: session.isPaused ? RecordingControlCopy.resume : RecordingControlCopy.pause)
        }
        .buttonStyle(
            RetainSecondaryButtonStyle(
                textStyle: RetainTypography.titleBarButton,
                padding: RetainMetrics.titleBarButtonPadding,
                cornerRadius: RetainMetrics.radiusExportButton,
                isFilled: true,
                border: RetainPalette.controlBorderEmphasisedSwatch
            )
        )
        .fixedSize()

        Button(action: shell.finish) {
            Text(verbatim: RecordingControlCopy.finish)
        }
        .buttonStyle(
            RetainSecondaryButtonStyle(
                textStyle: RetainTypography.titleBarButton,
                padding: RetainMetrics.titleBarButtonPadding,
                cornerRadius: RetainMetrics.radiusExportButton,
                isFilled: true,
                ink: RetainPalette.redInk,
                border: RetainPalette.redBorderSwatch
            )
        )
        .fixedSize()
    }

    var body: some View {
        HStack(spacing: RetainMetrics.titleBarGroupGap) {
            // The traffic lights are the system's and are drawn over this, so
            // the strip reserves their width rather than drawing into it.
            RetainTrafficLightSpace()

            Spacer(minLength: 0)

            HStack(spacing: RetainMetrics.titleBarSpeechGap) {
                RetainLevelMeter(
                    level: level,
                    barCount: RetainMetrics.meterBarCountTitleBar,
                    height: RetainMetrics.waveformHeightTitleBar,
                    appearance: isSpeaking ? .live : .idle
                )

                Text(verbatim: speechState)
                    .retainStyle(RetainTypography.titleBarStatus)
                    .foregroundStyle(isSpeaking ? RetainPalette.accent : RetainPalette.inkLabel)
            }

            Text(verbatim: microphoneLine)
                .retainStyle(RetainTypography.titleBarStatus)
                .foregroundStyle(RetainPalette.inkLabel)

            // Beside the microphone's state, because they are the same question
            // about the other half of the pipeline. It was lost when this bar
            // was rewritten to carry Pause and Finish.
            ModelStatusPill()

            // Pause and Finish were in the transcript rail's footer, and the
            // rail is gone — the transcript has the window. They belong with
            // the clock, which is the other thing in this bar that is about the
            // lecture rather than about the machine.
            if session.phase == .recording {
                controls
            }

            timerPill
        }
        .padding(RetainMetrics.titleBarPadding)
        .frame(height: RetainMetrics.titleBarHeight)
        // The same room under it as every other window's bar. This one is its
        // own view rather than a `RetainTitleBar` — it carries a level meter, a
        // clock and two controls — so the value is taken rather than inherited.
        .padding(.bottom, RetainMetrics.titleBarBottomRoom)
        .background(RetainPalette.surfaceTitleBar)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    private var timerPill: some View {
        HStack(spacing: RetainMetrics.titleBarTimerPillGap) {
            RetainStatusDot(
                colour: RetainPalette.redRecording,
                diameter: RetainMetrics.statusDotTimerPill,
                loop: session.isPaused ? nil : .recordingPulse
            )
            Text(verbatim: RetainTimeFormat.clock(session.recorder.duration))
                .retainStyle(RetainTypography.titleBarTimer)
                .foregroundStyle(RetainPalette.inkPrimary)
        }
        .padding(RetainMetrics.titleBarTimerPillPadding)
        .background(RetainPalette.surfaceInsetControl, in: Capsule())
        .overlay(Capsule().strokeBorder(RetainPalette.lineControlBorder, lineWidth: RetainMetrics.borderWidth))
    }

    // MARK: Copy

    private var level: AudioLevel? {
        session.recorder.state == .recording ? session.recorder.level : nil
    }

    private var isSpeaking: Bool {
        guard let level else { return false }
        return !level.isSilent
    }

    /// "Speaker detected" while somebody is talking.
    ///
    /// **The quiet half is not drawn.** Board 01 only has the speaking state in
    /// it, and the popover's ready card is where the word "Silence" comes from.
    private var speechState: String {
        isSpeaking
            ? String(localized: "Speaker detected", comment: "Title bar state while somebody is speaking")
            : String(localized: "Silence", comment: "Title bar state while nobody is speaking")
    }

    /// "Microphone on · 8.6 W", or the first half alone where the draw cannot
    /// be read — see `PowerDraw`, which can only answer on battery.
    private var microphoneLine: String {
        guard let watts = power.draw?.watts else {
            return String(localized: "Microphone on", comment: "Title bar state saying the microphone is open")
        }
        return String(
            localized: "Microphone on · \(watts.formatted(.number.precision(.fractionLength(1)))) W",
            comment: "Title bar state saying the microphone is open, with the live power reading in watts"
        )
    }
}

// MARK: - Meta strip

/// Topic, course and date, in a `1.6fr 1fr 1fr` grid.
struct RecordingMetaStrip: View {

    let session: LectureSession
    let courses: CourseSelection

    var body: some View {
        GeometryReader { geometry in
            let widths = Self.columnWidths(in: geometry.size.width)

            HStack(spacing: 0) {
                cell(
                    label: String(localized: "Topic · detected", comment: "Meta strip label above the topic the model reads out of the transcript"),
                    padding: RetainMetrics.metaStripCellFirst
                ) {
                    // The topic is derived from the finished transcript, so
                    // during the lecture there is nothing to draw. The label
                    // says as much, which is why it is not filled with a
                    // placeholder that would sort and search as a real topic.
                    Text(verbatim: session.topic ?? "")
                        .retainStyle(RetainTypography.metaValue)
                        .foregroundStyle(RetainPalette.inkPrimary)
                }
                .frame(width: widths[0])

                RetainVerticalDivider()

                cell(
                    label: String(localized: "Course", comment: "Meta strip label above the course a recording belongs to"),
                    padding: RetainMetrics.metaStripCellOther
                ) {
                    RecordingCoursePicker(session: session, courses: courses)
                }
                .frame(width: widths[1])

                RetainVerticalDivider()

                cell(
                    label: String(localized: "Date", comment: "Meta strip label above the day a recording was made"),
                    padding: RetainMetrics.metaStripCellOther
                ) {
                    Text(verbatim: Self.date(session.startedAt))
                        .retainStyle(RetainTypography.metaValue)
                        .foregroundStyle(RetainPalette.inkBody)
                }
                .frame(width: widths[2])
            }
        }
        .frame(height: Self.height)
        .background(RetainPalette.surfaceMetaStrip)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    private func cell<Value: View>(
        label: String,
        padding: EdgeInsets,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: RetainMetrics.metaValueGap) {
            RetainLabel(text: label)
            value()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The strip is as tall as its own padding plus a label and a value, and
    /// the export draws it that way rather than giving it a height. Measured
    /// from the two type styles so it follows them.
    static var height: CGFloat {
        RetainMetrics.metaStripCellFirst.top
            + RetainMetrics.metaStripCellFirst.bottom
            + RetainTypography.naturalLineHeight(of: RetainTypography.uppercaseLabel)
            + RetainMetrics.metaValueGap
            + RetainTypography.naturalLineHeight(of: RetainTypography.metaValue)
    }

    /// `1.6fr 1fr 1fr`, with the two one-pixel rules between them taken off
    /// first so the columns keep their ratio.
    static func columnWidths(in total: CGFloat) -> [CGFloat] {
        let weights = RetainMetrics.metaStripColumnWeights
        let available = max(0, total - CGFloat(weights.count - 1))
        let sum = weights.reduce(0, +)
        return weights.map { available * $0 / sum }
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year())
    }
}

/// The course, and the menu the chevron opens.
struct RecordingCoursePicker: View {

    let session: LectureSession
    let courses: CourseSelection

    var body: some View {
        Menu {
            ForEach(courses.courses) { course in
                Button {
                    session.changeCourse(to: course)
                } label: {
                    Text(verbatim: course.name)
                }
            }
        } label: {
            HStack(spacing: RetainMetrics.metaChevronGap) {
                Text(verbatim: session.course?.name ?? "")
                    .retainStyle(RetainTypography.metaValue)
                    .foregroundStyle(RetainPalette.inkPrimary)
                Text(verbatim: RetainGlyph.disclosure)
                    .retainStyle(RetainTypography.chevron)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        // `.button` with a plain button style, like `RetainPickerField`: the
        // borderless style keeps the label's text and drops everything around
        // it, which here would take the chevron with it.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(courses.courses.count < 2)
    }
}

// MARK: - Chrome

/// The one-pixel rule between two panes.
struct RetainVerticalDivider: View {
    var colour: Color = RetainPalette.lineDivider

    var body: some View {
        Rectangle()
            .fill(colour)
            .frame(width: RetainMetrics.borderWidth)
    }
}


// MARK: -

/// The two controls that end or hold a lecture.
///
/// They were in the transcript rail's footer, which the live screen no longer
/// has: the transcript takes the window and the rail is gone. The wording is
/// the rail's, unchanged.
nonisolated enum RecordingControlCopy {

    static var pause: String {
        String(localized: "Pause", comment: "Button that holds a running recording")
    }

    static var resume: String {
        String(localized: "Continue", comment: "Button that resumes a paused recording")
    }

    static var finish: String {
        String(localized: "Finish", comment: "Button that ends a recording and starts the summary")
    }
}
