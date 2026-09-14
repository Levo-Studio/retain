import Foundation

/// Everything board 02 draws, as a value.
///
/// The five cards read this rather than the session itself. Not ceremony: a
/// card that takes a `LectureSession` can only be looked at by starting a
/// lecture, which means a microphone, a gigabyte of models and three minutes of
/// somebody talking. A card that takes a value can be looked at, rendered to a
/// PNG and compared against the export in a test.
nonisolated struct PopoverSnapshot: Equatable, Sendable {

    var state: PopoverState

    /// The course the lecture belongs to. Empty before one is running.
    var courseName: String

    /// Seconds of recorded audio.
    var duration: TimeInterval

    var noteBlocks: Int
    var markers: Int

    /// The last few transcript lines, oldest first. The card takes as many as
    /// its ladder has rungs.
    var lines: [TranscriptLine]

    /// The level as the recorder last measured it, or `nil` when nothing is
    /// being recorded.
    var level: AudioLevel?

    /// The live power reading, or `nil` where it cannot be read — see
    /// `PowerDraw`, which can only answer on battery.
    var watts: Double?

    /// How far the passes after the recording have got, 0…1.
    var progress: Double

    /// The microphone the ready state names.
    var inputName: String

    /// Whether a recording may be started at all: there is a course to record
    /// into and the models are not still downloading.
    var canRecord: Bool

    init(
        state: PopoverState,
        courseName: String = "",
        duration: TimeInterval = 0,
        noteBlocks: Int = 0,
        markers: Int = 0,
        lines: [TranscriptLine] = [],
        level: AudioLevel? = nil,
        watts: Double? = nil,
        progress: Double = 0,
        inputName: String = "",
        canRecord: Bool = false
    ) {
        self.state = state
        self.courseName = courseName
        self.duration = duration
        self.noteBlocks = noteBlocks
        self.markers = markers
        self.lines = lines
        self.level = level
        self.watts = watts
        self.progress = progress
        self.inputName = inputName
        self.canRecord = canRecord
    }
}

// MARK: - Reading one off the shell

@MainActor
extension PopoverSnapshot {

    init(shell: ShellModel) {
        let session = shell.session
        let state = PopoverState.resolve(
            phase: session.phase,
            recorder: session.recorder.state,
            isConfirmingStop: shell.isConfirmingStop
        )

        self.init(
            state: state,
            courseName: session.course?.name ?? "",
            duration: session.recorder.duration,
            noteBlocks: session.notes.count,
            markers: session.markers.count,
            lines: session.lines,
            level: state == .running ? session.recorder.level : nil,
            watts: shell.power.draw?.watts,
            progress: PopoverSnapshot.progress(of: session.phase),
            inputName: PopoverSnapshot.inputName(of: session.recorder),
            canRecord: shell.courses.canRecord && session.phase != .preparingModels
        )
    }

    static func progress(of phase: LectureSession.Phase) -> Double {
        switch phase {
        case .transcribing(let fraction), .separatingSpeakers(let fraction): fraction
        default: 0
        }
    }

    /// The microphone that would be recorded from: the one the user chose, the
    /// system default otherwise.
    static func inputName(of recorder: RecordingEngine) -> String {
        let devices = recorder.devices
        if let uid = recorder.preferredDeviceUID,
           let chosen = devices.first(where: { $0.uid == uid }) {
            return chosen.name
        }
        if let id = InputDeviceList.defaultDeviceID(), let match = devices.first(where: { $0.id == id }) {
            return match.name
        }
        return devices.first?.name
            ?? String(localized: "No microphone", comment: "Shown instead of a microphone name when there is none")
    }
}
