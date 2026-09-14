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

    /// Keyed by recording id, so a second click finds the first window.
    private var detailWindows: [Int64: NSWindow] = [:]

    init(database: RetainDatabase) {
        self.database = database
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
        // The dialogs belong to Settings, which owns board 07. Until the
        // library carries its own presentation, these stay unset rather than
        // pretending: an unset closure draws the control unavailable, which is
        // honest, where a closure that did nothing would look broken.
        self.model = model

        let hosting = NSHostingController(rootView: LibraryView(model: model))
        let window = makeWindow(
            around: hosting,
            size: RetainMetrics.detailWindowSize,
            title: String(localized: "Library", comment: "Title of the library window")
        )
        self.window = window
        bringForward(window)

        Task { await model.load() }
    }

    // MARK: - A recording

    func openDetail(for recording: Recording, at time: TimeInterval? = nil) {
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
