import AppKit
import Observation

/// Owns Retain's entry in the status bar.
///
/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: a `MenuBarExtra` still
/// cannot be opened programmatically, so it cannot be opened by a keyboard
/// shortcut, and Retain's whole point is that you reach it without taking your
/// hands off the keyboard in the middle of a lecture.
///
/// The menu here is scaffolding. Design board 02 draws a popover with five
/// states, and that is what replaces this in phase 6; what a plain menu buys in
/// the meantime is that the recording path can be exercised at all.
@MainActor
final class StatusItemController {

    private let item: NSStatusItem
    private let engine = RecordingEngine()
    private var observation: NSObjectProtocol?
    private var stateTracking: Task<Void, Never>?

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // `waveform` stands in until the menu-bar glyph is drawn. The design
        // export has no status-bar icon on any board, and inventing one is the
        // owner's call, not a gap to fill with taste.
        let image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: String(localized: "Retain", comment: "Accessibility label of the status bar item")
        )
        // A template image is what lets the status bar tint the glyph itself,
        // so it stays legible in a light menu bar, a dark one, and under an
        // accent tint, without Retain tracking the appearance.
        image?.isTemplate = true
        item.button?.image = image

        item.menu = makeMenu()
        observeEngine()
    }

    deinit {
        MainActor.assumeIsolated {
            stateTracking?.cancel()
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Menu

    private var recordItem: NSMenuItem?
    private var statusItemRow: NSMenuItem?

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusItemRow = status

        menu.addItem(.separator())

        let record = menu.addItem(
            withTitle: String(localized: "Start Recording", comment: "Status bar menu item starting a recording"),
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        record.target = self
        recordItem = record

        menu.addItem(
            withTitle: String(localized: "Reveal Recordings in Finder", comment: "Status bar menu item opening the recordings folder"),
            action: #selector(revealRecordings),
            keyEquivalent: ""
        ).target = self

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

        updateMenu()
        return menu
    }

    /// Follows the engine's observable state.
    ///
    /// `withObservationTracking` fires once per change, so it re-arms itself
    /// after every one. A timer reading the same values would be the wrong
    /// shape twice over: it would tick while nothing is recording, and it would
    /// still miss a change that happened between two ticks.
    private func observeEngine() {
        stateTracking?.cancel()
        stateTracking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let changed: Void? = await withCheckedContinuation { continuation in
                    withObservationTracking {
                        self?.updateMenu()
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard changed != nil else { return }
            }
        }
    }

    private func updateMenu() {
        switch engine.state {
        case .idle:
            statusItemRow?.title = String(localized: "Not recording",
                                          comment: "Status bar menu header while idle")
            recordItem?.title = String(localized: "Start Recording",
                                       comment: "Status bar menu item starting a recording")

        case .recording:
            statusItemRow?.title = String(
                localized: "Recording · \(Self.elapsed(engine.duration))",
                comment: "Status bar menu header while recording, with elapsed time"
            )
            recordItem?.title = String(localized: "Stop Recording",
                                       comment: "Status bar menu item stopping a recording")

        case .paused:
            statusItemRow?.title = String(localized: "Paused", comment: "Status bar menu header while paused")
            recordItem?.title = String(localized: "Stop Recording",
                                       comment: "Status bar menu item stopping a recording")

        case .failed(let message):
            statusItemRow?.title = message
            recordItem?.title = String(localized: "Start Recording",
                                       comment: "Status bar menu item starting a recording")
        }
    }

    private static func elapsed(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%02d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        Task { @MainActor in
            if engine.state == .recording || engine.state == .paused {
                await engine.finish()
            } else {
                await engine.start(writingTo: RecordingStore.newRecordingURL())
            }
        }
    }

    @objc private func revealRecordings() {
        let directory = RecordingStore.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
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
}
