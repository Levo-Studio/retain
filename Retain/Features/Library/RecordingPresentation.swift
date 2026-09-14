import Foundation

/// What the library table shows for one recording.
///
/// Pulled out of the view because the interesting case is the one the board
/// cannot draw: **a recording with no topic.** The model derives the topic and
/// may never have run, so the column is nullable all the way down, and what
/// goes in it instead is a decision rather than a formatting detail.
nonisolated enum RecordingPresentation {

    /// The Topic column.
    ///
    /// A recording the model never got a topic out of shows **when it
    /// happened** — not an em dash, not "Untitled", not the course name. A
    /// placeholder would sort and read as if it were a real topic, and the
    /// date and time of day are what a recording is identified by anyway, so
    /// they are the honest answer rather than a stand-in for one.
    static func title(
        of recording: Recording,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        if let topic = recording.topic, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return topic
        }
        return recording.startedAt.formatted(
            styled(.dateTime.day().month(.wide).year().hour().minute(), locale, timeZone)
        )
    }

    /// `Date.FormatStyle` takes its locale and time zone as properties rather
    /// than as builder calls, and both are arguments here so a test can ask for
    /// a fixed one instead of the machine's.
    private static func styled(
        _ style: Date.FormatStyle,
        _ locale: Locale,
        _ timeZone: TimeZone
    ) -> Date.FormatStyle {
        var style = style
        style.locale = locale
        style.timeZone = timeZone
        return style
    }

    /// Whether the Topic column is showing a topic or standing in for one. The
    /// export draws the title in two inks and this is not what decides which —
    /// it is here so a caller can tell the difference without comparing strings.
    static func hasTopic(_ recording: Recording) -> Bool {
        guard let topic = recording.topic else { return false }
        return !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The Started column: which day, and the time of day.
    ///
    /// The export draws the day alone — "Heute", "7. Sep" — because it had a
    /// lesson number to tell two recordings apart with. There is none, so the
    /// time of day is the other half of a recording's identity and it is drawn.
    static func started(
        of recording: Recording,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone

        let time = recording.startedAt.formatted(
            styled(.dateTime.hour().minute(), locale, timeZone)
        )

        let day = calendar.isDate(recording.startedAt, inSameDayAs: now)
            ? LibraryCopy.today
            : recording.startedAt.formatted(
                styled(.dateTime.day().month(.abbreviated), locale, timeZone)
            )

        return LibraryCopy.startedAt(day: day, time: time)
    }

    /// The Duration column. Zero seconds is a recording that has not run long
    /// enough to have a length yet, and an empty cell says that better than
    /// "0 min" does.
    static func duration(of recording: Recording) -> String {
        guard recording.duration > 0 else { return "" }
        return LibraryCopy.minutes(RetainTimeFormat.wholeMinutes(recording.duration))
    }

    /// The Status column.
    ///
    /// The board draws two of the four — `läuft` and `fertig`. The other two
    /// are where a recording sits between them, and a recording stuck in either
    /// has to be tellable from a finished one, so they are named rather than
    /// folded into "done".
    static func state(of recording: Recording) -> String {
        switch recording.state {
        case .recording: LibraryCopy.stateRecording
        case .transcribing: LibraryCopy.stateTranscribing
        case .summarizing: LibraryCopy.stateSummarizing
        case .done: LibraryCopy.stateDone
        }
    }

    /// Only a running recording is drawn in the red ink; everything else is a
    /// label. The board draws the running row picked out with the meta-strip
    /// colour behind it too.
    static func isRunning(_ recording: Recording) -> Bool {
        recording.state == .recording
    }

    /// "13 h 24 min", or "47 min" for a course that has not run to an hour yet.
    static func total(_ seconds: TimeInterval) -> String {
        guard RetainTimeFormat.spansAnHour(seconds) else {
            return LibraryCopy.minutes(RetainTimeFormat.wholeMinutes(seconds))
        }
        let split = RetainTimeFormat.hoursAndMinutes(seconds)
        return LibraryCopy.hoursAndMinutes(hours: split.hours, minutes: split.minutes)
    }
}
