import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// Owns Retain's entry in the status bar and the popover that hangs off it.
///
/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: a `MenuBarExtra` still
/// cannot be opened programmatically, so it cannot be opened by a keyboard
/// shortcut, and Retain's whole point is that you reach it without taking your
/// hands off the keyboard in the middle of a lecture.
///
/// The button's own action is a click; `KeyboardShortcuts` is the other way in.
/// Both end in `toggle`, so there is one path and one state.
@MainActor
final class StatusItemController {

    private let item: NSStatusItem
    private let shell: ShellModel
    private let recordingWindow: RecordingWindowController
    private let settingsWindow: SettingsWindowController
    private let libraryWindow: LibraryWindowController?

    private var panel: PopoverPanel?
    private var resignObserver: (any NSObjectProtocol)?
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

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // The mark from the repository, not an SF Symbol: the owner settled
        // that the status bar wears the same waveform as the app icon.
        //
        // It is a template image, which is what lets the status bar paint the
        // glyph itself — so it stays legible in a light menu bar, a dark one,
        // and under an accent tint, without Retain tracking the appearance.
        // The asset carries that intent, so nothing has to set isTemplate here.
        let image = NSImage(named: "MenuBarIcon")
        image?.accessibilityDescription = String(
            localized: "Retain",
            comment: "Accessibility label of the status bar item"
        )
        item.button?.image = image
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        registerShortcuts()
        followPhase()
    }

    deinit {
        MainActor.assumeIsolated {
            phaseTracking?.cancel()
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
            }
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Opening and closing

    @objc func toggle() {
        // A right-click gets the housekeeping menu instead of the popover.
        // Board 02 draws no Quit, and an accessory app with no window open has
        // no menu bar to put one in, so without this there is no way out of
        // Retain but Force Quit.
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if panel?.isVisible == true {
            close()
        } else {
            open()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(
            withTitle: String(localized: "Reveal Recordings in Finder",
                              comment: "Status bar menu item opening the recordings folder"),
            action: #selector(revealRecordings),
            keyEquivalent: ""
        ).target = self

        let library = menu.addItem(
            withTitle: String(localized: "Library…", comment: "Status bar menu item opening the library window"),
            action: #selector(showLibrary),
            keyEquivalent: "l"
        )
        library.keyEquivalentModifierMask = [.command]
        library.target = self
        library.isEnabled = libraryWindow != nil

        let settings = menu.addItem(
            withTitle: String(localized: "Settings…", comment: "Status bar menu item opening the settings window"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self

        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "About Retain", comment: "Status bar menu item opening the about panel"),
            action: #selector(showAbout),
            keyEquivalent: ""
        ).target = self

        menu.addItem(
            withTitle: String(localized: "Quit Retain", comment: "Status bar menu item quitting the app"),
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        // Assigned, popped up, and taken away again: an item that keeps a menu
        // has no click action left for the popover.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

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
        // An accessory app has no menu bar of its own, so the standard about
        // panel has to be asked for by hand — and the app has to come forward
        // first, or the panel opens behind whatever the user was reading.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func open() {
        guard let button = item.button else { return }

        // The courses are re-read every time rather than once at launch: a
        // course created in the library while the popover was shut has to be in
        // the list the next time it opens.
        Task { await shell.courses.reload() }

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.present(under: button)
    }

    func close() {
        shell.isConfirmingStop = false
        panel?.orderOut(nil)
    }

    private func makePanel() -> PopoverPanel {
        let root = PopoverRoot(shell: shell, actions: actions)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]

        let panel = PopoverPanel(content: host)

        // A popover that outlives the click that opened it is a popover in the
        // way. Closing on resign is what every menu-bar window on this platform
        // does, and it is also what makes Escape and a click elsewhere behave
        // the same.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Except when the popover gave key to one of its own children.
                // The course field opens its list in a panel attached to this
                // one — see `RetainDropdownPanel` — and a popover that shut the
                // moment a picker opened would be a course field that cannot be
                // used.
                guard panel.childWindows?.isEmpty != false else { return }
                self?.close()
            }
        }

        return panel
    }

    private var actions: PopoverActions {
        PopoverActions(
            record: { [weak self] in
                self?.shell.record()
            },
            pause: { [weak self] in
                self?.shell.pause()
            },
            resume: { [weak self] in
                self?.shell.resume()
            },
            requestStop: { [weak self] in
                self?.shell.requestStop()
            },
            finish: { [weak self] in
                self?.shell.finish()
            },
            annotate: { [weak self] text in
                self?.shell.annotate(text)
            },
            openRecordingWindow: { [weak self] in
                self?.close()
                self?.recordingWindow.show()
            },
            dismiss: { [weak self] in
                self?.close()
            }
        )
    }

    // MARK: - Shortcuts

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .togglePopover) { [weak self] in
            self?.toggle()
        }

        KeyboardShortcuts.onKeyUp(for: .annotate) { [weak self] in
            guard let self else { return }
            // The window if it is open, the popover otherwise: `⌘⇧M` is meant
            // to put the caret somewhere the user can type, and which of the
            // two that is depends on what is already on screen.
            if recordingWindow.isOpen {
                recordingWindow.show()
            } else {
                open()
            }
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

        item.button?.toolTip = switch shell.session.phase {
        case .idle, .done, .failed:
            String(localized: "Retain", comment: "Accessibility label of the status bar item")
        case .preparingModels:
            String(localized: "Downloading speech models",
                   comment: "Status bar tooltip during the one-time model download")
        case .recording:
            shell.session.isPaused
                ? String(localized: "Paused", comment: "Status bar tooltip while a recording is paused")
                : String(localized: "Recording · \(RetainTimeFormat.clock(shell.session.recorder.duration))",
                         comment: "Status bar tooltip while recording, with elapsed time")
        case .transcribing, .separatingSpeakers:
            String(localized: "Summarizing", comment: "Status bar tooltip while the passes after a recording run")
        }
    }
}

// MARK: - The popover's root

/// Re-reads the shell every time anything it holds changes.
///
/// `PopoverView` takes values rather than the model so the five cards can be
/// looked at without one; this is the one place that turns the model into those
/// values, and it is what makes SwiftUI observe them.
struct PopoverRoot: View {

    let shell: ShellModel
    let actions: PopoverActions

    var body: some View {
        PopoverView(
            snapshot: PopoverSnapshot(shell: shell),
            courses: shell.courses,
            actions: actions
        )
    }
}
