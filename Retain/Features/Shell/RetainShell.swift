import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// Holds the app's windows and the one shell they all read from.
///
/// **There is no status bar item any more.** Retain wore one from the first
/// commit — it is in the locked decisions as `NSStatusItem` + `NSPanel` — and
/// the owner asked for it to go: an icon to hunt for in a row of twenty, with
/// everything worth reaching hidden behind a click on it. The popover went with
/// it, because it was anchored under that button and the recording window is
/// the full-sized version of everything it held.
///
/// What replaced it is ordinary: the library is the app's home window and
/// carries Record, the application menu carries Settings and Library with their
/// shortcuts, and the Dock tile brings the library back. The global shortcuts
/// still work from any app, which is what they were for — a hand does not leave
/// the keyboard in the middle of a lecture.
@MainActor
final class RetainShell {

    private let shell: ShellModel
    private let recordingWindow: RecordingWindowController
    private let settingsWindow: SettingsWindowController
    private let libraryWindow: LibraryWindowController?

    private var phaseTracking: Task<Void, Never>?

    init(store: LectureStore?) {
        shell = ShellModel(store: store)
        recordingWindow = RecordingWindowController(shell: shell)
        let library = store.map { LibraryWindowController(database: $0.database) }
        libraryWindow = library
        settingsWindow = SettingsWindowController(
            model: SettingsModel(
                speechModels: shell.session.models,
                recorder: shell.session.recorder,
                library: store?.library
            )
        )
        // The library's Record button goes through the same shell as the
        // popover's, so there is one answer to "is Retain busy" and one place a
        // recording starts.
        library?.startRecording = { [shell, recordingWindow] course, term in
            shell.record(course, during: term)
            recordingWindow.show()
        }
        library?.canRecord = { [shell] in shell.canRecord }

        // **No item in the menu bar.** Retain wore one from the first commit and
        // the owner asked for it to go: an icon that has to be hunted for in a
        // row of twenty, with everything worth reaching behind a click on it.
        // Everything it offered has a better home now — the library window is
        // the app's home and carries Record, the application menu carries
        // Settings and Library with their shortcuts, and the Dock tile brings
        // the library back.
        //
        // The popover went with it. It was anchored under the item's button and
        // there is no button any more; the recording window is the surface it
        // was a small copy of.
        registerShortcuts()
        followPhase()
    }

    deinit {
        MainActor.assumeIsolated {
            phaseTracking?.cancel()
        }
    }

    // MARK: - Opening windows

    @objc private func revealRecordings() {
        let directory = RecordingStore.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    @objc private func showLibrary() {
        showLibraryWindow()
    }

    /// Also the answer to a click on the Dock tile with nothing open.
    func showLibraryWindow() {
        libraryWindow?.show()
    }

    @objc private func showSettings() {
        showSettingsWindow()
    }

    /// Also the answer to ⌘, from the application menu.
    func showSettingsWindow() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        // The app has to come forward first, or the panel opens behind
        // whatever the user was reading.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Shortcuts

    private func registerShortcuts() {
        // The shortcut that used to open the popover. It brings the library
        // forward instead — the window the app is now built around, and the
        // one place a recording starts.
        KeyboardShortcuts.onKeyUp(for: .togglePopover) { [weak self] in
            self?.showLibraryWindow()
        }

        KeyboardShortcuts.onKeyUp(for: .annotate) { [weak self] in
            guard let self else { return }
            // Always the recording window. It used to be the window if it was
            // open and the popover otherwise; there is no popover now, and the
            // window is where the composer is. `⌘⇧M` has to put the caret
            // somewhere the user can type, so it brings the window forward
            // whether or not it was on screen.
            recordingWindow.show()
            shell.focusAnnotation()
        }

        KeyboardShortcuts.onKeyUp(for: .resumeRecording) { [weak self] in
            self?.shell.resume()
        }
    }

    // MARK: - Following the lecture

    /// Keeps the status item's accessibility label and the power sampling in
    /// step with the lecture.
    ///
    /// `withObservationTracking` fires once per change, so it re-arms itself
    /// after every one. A timer reading the same values would be the wrong
    /// shape twice over: it would tick while nothing is recording, and it would
    /// still miss a change that happened between two ticks.
    private func followPhase() {
        phaseTracking?.cancel()
        phaseTracking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let changed: Void? = await withCheckedContinuation { continuation in
                    withObservationTracking {
                        self?.applyPhase()
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard changed != nil else { return }
            }
        }
    }

    private func applyPhase() {
        shell.followPower()
    }
}
