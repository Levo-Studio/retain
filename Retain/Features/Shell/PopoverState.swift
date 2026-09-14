import Foundation

/// Which of board 02's five cards the popover is showing.
///
/// The five are drawn side by side in the export, which says what each looks
/// like and not when each appears. This is that second half, and it is a
/// function rather than a field so that the popover cannot drift out of step
/// with the lecture: there is one source of truth — the session — and the card
/// is read off it.
///
/// Only one of the five is not a phase of a lecture. `stopConfirmation` is a
/// question the user was asked and has not answered yet, so it lives in the
/// popover and is passed in here.
nonisolated enum PopoverState: String, Sendable, Equatable, CaseIterable {

    /// Nothing is recording. The course picker and the Record button.
    case ready

    /// A lecture is running: timer, meter, live transcript, annotation bar.
    case running

    /// "Pause holds immediately … Finish closes the recording."
    case stopConfirmation

    /// Recording, microphone closed. `⌘⇧P` resumes.
    case paused

    /// The passes after the microphone stops.
    case summarizing

    // MARK: - Reading it off the session

    /// - Parameters:
    ///   - phase: where the lecture is.
    ///   - recorder: whether the microphone is actually open, which `phase`
    ///     does not say — a paused lecture is still `.recording`, because the
    ///     file, the transcriber and the block boundaries all stay open across
    ///     a pause.
    ///   - isConfirmingStop: the user pressed Stop and has not answered yet.
    ///
    /// On the main actor because `RecordingEngine.State`'s own `Equatable`
    /// conformance is: the engine is a main-actor type, and comparing two of
    /// its states off that actor is not something the compiler will allow.
    @MainActor
    static func resolve(
        phase: LectureSession.Phase,
        recorder: RecordingEngine.State,
        isConfirmingStop: Bool
    ) -> PopoverState {
        switch phase {
        case .recording:
            if isConfirmingStop { return .stopConfirmation }
            return recorder == .paused ? .paused : .running

        case .transcribing, .separatingSpeakers:
            return .summarizing

        // The one-time model download has no card on board 02 — board 06 draws
        // it, in Settings, with its megabytes and its estimate. Until the owner
        // says what the popover shows meanwhile, it shows the ready state with
        // the Record button unavailable, which is at least true.
        case .idle, .preparingModels, .done, .failed:
            return .ready
        }
    }
}
