import Testing

@testable import Retain

/// Board 02 draws five cards and says what each looks like. Which one appears
/// when is the half that is not drawn, and it is the half that can be wrong.
@MainActor
@Suite("Popover state")
struct PopoverStateTests {

    @Test("Nothing recording is the ready state", arguments: [
        LectureSession.Phase.idle,
        .preparingModels,
        .done,
        .failed("the models could not be loaded"),
    ])
    func idlePhasesAreReady(phase: LectureSession.Phase) {
        #expect(PopoverState.resolve(phase: phase, recorder: .idle, isConfirmingStop: false) == .ready)
    }

    @Test("A running lecture is the running state")
    func recordingIsRunning() {
        #expect(PopoverState.resolve(phase: .recording, recorder: .recording, isConfirmingStop: false) == .running)
    }

    @Test("A pause is the recorder's business, not the phase's")
    func pausedRecorderIsPaused() {
        // The lecture is still `.recording`: the file, the transcriber and the
        // block boundaries all stay open across a pause. Only the microphone
        // stops, and only the recorder knows it.
        #expect(PopoverState.resolve(phase: .recording, recorder: .paused, isConfirmingStop: false) == .paused)
    }

    @Test("Stop asks before it ends a lecture")
    func stopAsksFirst() {
        #expect(PopoverState.resolve(phase: .recording, recorder: .recording, isConfirmingStop: true) == .stopConfirmation)
    }

    @Test("The confirmation outranks a pause, because it is what was just asked")
    func confirmationOutranksPause() {
        #expect(PopoverState.resolve(phase: .recording, recorder: .paused, isConfirmingStop: true) == .stopConfirmation)
    }

    @Test("Both passes after the microphone closes read as summarizing", arguments: [
        LectureSession.Phase.transcribing(0),
        .transcribing(0.6),
        .separatingSpeakers(0.2),
    ])
    func passesAreSummarizing(phase: LectureSession.Phase) {
        #expect(PopoverState.resolve(phase: phase, recorder: .idle, isConfirmingStop: false) == .summarizing)
    }

    @Test("A confirmation left over from a finished lecture does not hold the card")
    func confirmationDoesNotSurviveTheLecture() {
        // Finishing is what the confirmation asks for, so the card it belongs
        // to has to go when the lecture does — otherwise the popover keeps
        // offering to stop a recording that already stopped.
        #expect(PopoverState.resolve(phase: .transcribing(0), recorder: .idle, isConfirmingStop: true) == .summarizing)
        #expect(PopoverState.resolve(phase: .idle, recorder: .idle, isConfirmingStop: true) == .ready)
    }

    // MARK: - What the card is drawn from

    @Test("Progress is only meaningful while the passes run")
    func progressFollowsThePhase() {
        #expect(PopoverSnapshot.progress(of: .transcribing(0.25)) == 0.25)
        #expect(PopoverSnapshot.progress(of: .separatingSpeakers(0.75)) == 0.75)
        #expect(PopoverSnapshot.progress(of: .recording) == 0)
        #expect(PopoverSnapshot.progress(of: .idle) == 0)
    }
}
