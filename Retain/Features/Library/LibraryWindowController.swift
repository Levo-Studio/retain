import AppKit
import SwiftUI

/// The library window, and the detail windows that open out of it.
///
/// One controller for both because they are one navigation: a recording is
/// reached by clicking its row, and the row is in the library. Splitting them
/// would mean the library holding a reference to a second controller only so it
/// could ask it to open something.
///
/// Detail windows are kept one per recording. Clicking the same row twice
/// brings the window that is already open to the front rather than opening a
/// second copy of the same lecture, which is what every document-shaped app on
/// this platform does and what a user expects without being told.
@MainActor
final class LibraryWindowController: NSObject, NSWindowDelegate {

    private let database: RetainDatabase
    private var window: NSWindow?
    private var model: LibraryModel?

    /// What the library's Record button does, and whether it can be pressed.
    ///
    /// Handed in rather than reached for: the library knows about a database
    /// and nothing else, and a window that could start a recording by talking
    /// to the shell directly would be a second place that decides when
    /// recording is allowed.
    var startRecording: ((Course, Term) -> Void)?
    var canRecord: () -> Bool = { false }

    /// How long the running lecture has been going. See
    /// `LibraryModel.lectureDuration`.
    var recordingDuration: () -> TimeInterval = { 0 }

    /// Ends the lecture that is running.
    var finishRecording: (() -> Void)?

    /// Keyed by recording id, so a second click finds the first window.
    private var detailWindows: [Int64: NSWindow] = [:]

    init(database: RetainDatabase) {
        self.database = database
    }

    /// Told by the shell whenever the lecture starts or stops, so the window's
    /// button can be Record or Finish without polling anything.
    private(set) var isLectureRunning = false

    func lectureIsRunning(_ running: Bool) {
        isLectureRunning = running
        model?.lectureIsRunning(running)
    }

    // MARK: - The library

    func show() {
        if let window {
            bringForward(window)
            return
        }

        let model = LibraryModel(database: database)
        model.onOpenRecording = { [weak self] recording, time in
            self?.openDetail(for: recording, at: time)
        }
        model.onOpenMerged = { [weak self] recording in
            self?.openDetail(for: recording, analysing: true)
        }
        model.onRecord = { [weak self] course, term in
            self?.startRecording?(course, term)
        }
        model.canRecord = { [weak self] in self?.canRecord() ?? false }
        model.onFinish = { [weak self] in self?.finishRecording?() }
        model.lectureDuration = { [weak self] in self?.recordingDuration() ?? 0 }
        model.lectureIsRunning(isLectureRunning)
        self.model = model

        let hosting = NSHostingController(rootView: LibraryView(model: model))
        let window = makeWindow(
            around: hosting,
            size: RetainMetrics.detailWindowSize,
            title: String(localized: "Library", comment: "Title of the library window")
        )
        self.window = window
        bringForward(window)
        // No load here: `LibraryView` starts `follow()`, whose first element
        // arrives immediately. Loading as well would read the library twice
        // every time the window opens.
    }

    // MARK: - A recording

    /// Opens a recording by id, reading the row first.
    ///
    /// For the hand-over at the end of a lecture: the recording window knows
    /// the id and nothing else, and a window controller is the right place to
    /// turn one into a row.
    func openRecording(_ id: Int64) async {
        guard let recording = try? await LibraryRepository(database).recording(id) else { return }
        openDetail(for: recording)
    }

    /// - Parameter analysing: start writing the notes as soon as the window has
    ///   read the recording. Used after a merge, where the lecture that comes
    ///   out has a whole transcript and no notes at all — leaving the reader to
    ///   find the button would be leaving them in front of an empty page whose
    ///   one available action they have to guess at.
    func openDetail(
        for recording: Recording,
        at time: TimeInterval? = nil,
        analysing: Bool = false
    ) {
        guard let id = recording.id else { return }

        if let existing = detailWindows[id] {
            bringForward(existing)
            return
        }

        let model = RecordingDetailModel(recording: recording, database: database)
        let hosting = NSHostingController(rootView: RecordingDetailView(model: model))
        let window = makeWindow(
            around: hosting,
            size: RetainMetrics.detailWindowSize,
            title: recording.topic ?? RecordingPresentation.started(of: recording)
        )
        detailWindows[id] = window
        bringForward(window)

        Task {
            await model.load()
            if let time { model.seek(to: time) }
            // After the load, so the model is running over the transcript the
            // window has actually read. The notes column shows the steps for
            // it, the same way it does for Re-analyse.
            if analysing { await model.writeNotes() }
        }
    }

    // MARK: - Windows

    private func makeWindow(around hosting: NSViewController, size: CGSize, title: String) -> NSWindow {
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = title
        window.isMovableByWindowBackground = true

        // Dark only. The export has no light board, so there is no light
        // appearance for a window to follow the system into.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black

        window.setContentSize(size)
        window.contentMinSize = RetainMetrics.windowMinimumSize
        window.center()
        window.delegate = self
        return window
    }

    private func bringForward(_ window: NSWindow) {
        // An accessory app has to be raised to regular before it can take key,
        // or the window appears behind whatever the user was reading.
        WindowPresence.opened()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }

        if closing === window {
            window = nil
            model = nil
        }
        detailWindows = detailWindows.filter { $0.value !== closing }

        // The policy drops back to accessory when the last window of any kind
        // has gone, which is the tally's job rather than this controller's.
        WindowPresence.closed()
    }
}
