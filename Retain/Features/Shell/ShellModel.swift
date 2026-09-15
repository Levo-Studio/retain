import Foundation
import Observation

/// Everything both of Retain's surfaces read from.
///
/// The popover and the recording window are two views of one lecture, not two
/// features that happen to talk to the same session — pausing in the popover
/// has to stop the window's timer in the same frame. Holding the session, the
/// course picker, the power reading and the two pieces of transient interface
/// state in one observable object is what makes that true by construction.
@MainActor
@Observable
final class ShellModel {

    let session: LectureSession
    let courses: CourseSelection
    let power = PowerDrawMonitor()

    /// The user pressed Stop and has not answered yet. Not part of the
    /// lecture — nothing about the recording has changed — so it lives here and
    /// not in the session.
    var isConfirmingStop = false

    /// Bumped every time `⌘⇧M` is pressed.
    ///
    /// A counter rather than a flag: pressing the shortcut twice in a row has
    /// to put the caret back in the composer both times, and a flag that is
    /// already `true` is a second press that does nothing.
    private(set) var annotationFocusRequests = 0

    init(store: LectureStore?) {
        session = LectureSession(store: store)
        courses = CourseSelection(library: store?.library)
    }

    /// A shell over a session that is not running, for rendering board 01.
    init(session: LectureSession, courses: CourseSelection) {
        self.session = session
        self.courses = courses
    }

    // MARK: - Verbs

    /// A recording needs a course **and** the term it is being made in: the row
    /// carries both, and the term cannot be worked out from the date afterwards
    /// because a term's period is optional. The picker holds both, which is why
    /// it is asked for both here.
    func record() {
        guard let course = courses.selected, let term = courses.term else { return }
        record(course, during: term)
    }

    /// Starts a recording for a course the caller names.
    ///
    /// The library window needs this: it is a list of courses, and the one the
    /// reader is looking at is the one they want to record — going back to the
    /// menu bar to pick the same course again in a second picker is a step that
    /// only exists because the two surfaces did not talk.
    ///
    /// The picker is moved onto that course as well, so the popover and the
    /// recording window agree with the library about what is being recorded.
    func record(_ course: Course, during term: Term) {
        // Nothing is started on top of a lecture that is still running or
        // still being transcribed. `start` would refuse it anyway; refusing it
        // here is what lets the button be drawn unavailable instead.
        guard canRecord else { return }
        courses.select(course)
        Task { await session.start(in: course, during: term) }
    }

    /// Whether a new recording can begin at all.
    ///
    /// Read by the library's Record button as well as the popover's, so the two
    /// cannot disagree about whether Retain is busy.
    var canRecord: Bool {
        switch session.phase {
        case .idle, .done, .failed: true
        case .preparingModels, .recording, .transcribing, .separatingSpeakers: false
        }
    }

    func pause() {
        isConfirmingStop = false
        session.pause()
    }

    func resume() {
        session.resume()
    }

    func requestStop() {
        isConfirmingStop = true
    }

    func finish() {
        isConfirmingStop = false
        Task { await session.stop() }
    }

    func annotate(_ text: String) {
        session.addMarker(text)
    }

    func focusAnnotation() {
        annotationFocusRequests += 1
    }

    /// The power reading is only sampled while there is a recording to read it
    /// against, which is what keeps a Mac sitting in the menu bar from waking
    /// every five seconds for a number nobody is looking at.
    func followPower() {
        if session.phase == .recording {
            power.start()
        } else {
            power.stop()
        }
    }
}
