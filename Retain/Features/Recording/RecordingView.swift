import SwiftUI

// MARK: - Root

/// Board 01: the title bar, the meta strip, the notes on the left and the live
/// transcript on the right.
struct RecordingRoot: View {

    let shell: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            RecordingTitleBar(session: shell.session, power: shell.power)
            RecordingMetaStrip(session: shell.session, courses: shell.courses)

            HStack(spacing: 0) {
                NotesPane(shell: shell)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                TranscriptRail(shell: shell)
                    .frame(width: RetainMetrics.transcriptRailWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .background(RetainPalette.surfaceWindow)
        .task { await shell.courses.reload() }
    }
}

// MARK: - Title bar

/// 38 points tall, with the traffic lights on the left and the state of the
/// microphone on the right.
struct RecordingTitleBar: View {

    let session: LectureSession
    let power: PowerDrawMonitor

    var body: some View {
        HStack(spacing: RetainMetrics.titleBarGroupGap) {
            // The traffic lights are the system's and are drawn over this, so
            // the left of the bar is deliberately empty.
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

            timerPill
        }
        .padding(RetainMetrics.titleBarPadding)
        .frame(height: RetainMetrics.titleBarHeight)
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
            Text(verbatim: ElapsedTime.clock(session.recorder.duration))
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
