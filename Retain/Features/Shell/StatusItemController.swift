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
/// the meantime is that the lecture path can be exercised at all.
@MainActor
final class StatusItemController {

    private let item: NSStatusItem
    private let session = LectureSession()
    private var stateTracking: Task<Void, Never>?

    private var headerRow: NSMenuItem?
    private var detailRow: NSMenuItem?
    private var recordRow: NSMenuItem?

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
        observeSession()
    }

    deinit {
        MainActor.assumeIsolated {
            stateTracking?.cancel()
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        headerRow = header

        let detail = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)
        detailRow = detail

        menu.addItem(.separator())

        let record = menu.addItem(
            withTitle: "",
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        record.target = self
        recordRow = record

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

    /// Follows the session's observable state.
    ///
    /// `withObservationTracking` fires once per change, so it re-arms itself
    /// after every one. A timer reading the same values would be the wrong
    /// shape twice over: it would tick while nothing is recording, and it would
    /// still miss a change that happened between two ticks.
    private func observeSession() {
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
        let start = String(localized: "Start Recording", comment: "Status bar menu item starting a recording")
        let stop = String(localized: "Stop Recording", comment: "Status bar menu item stopping a recording")

        switch session.phase {
        case .idle:
            headerRow?.title = String(localized: "Not recording", comment: "Status bar menu header while idle")
            detailRow?.isHidden = true
            recordRow?.title = start
            recordRow?.isEnabled = true

        case .preparingModels:
            headerRow?.title = String(localized: "Downloading speech models",
                                      comment: "Status bar menu header during the one-time model download")
            detailRow?.isHidden = false
            detailRow?.title = Self.percentage(session.downloadFraction)
            recordRow?.title = start
            recordRow?.isEnabled = false

        case .recording:
            headerRow?.title = String(
                localized: "Recording · \(Self.elapsed(session.recorder.duration))",
                comment: "Status bar menu header while recording, with elapsed time"
            )
            detailRow?.isHidden = false
            detailRow?.title = session.partial.isEmpty
                ? String(localized: "\(session.lines.count) lines", comment: "Number of transcript lines so far")
                : Self.trimmed(session.partial)
            recordRow?.title = stop
            recordRow?.isEnabled = true

        case .transcribing(let fraction):
            headerRow?.title = String(localized: "Transcribing", comment: "Status bar menu header during the batch pass")
            detailRow?.isHidden = false
            detailRow?.title = Self.percentage(fraction)
            recordRow?.title = start
            recordRow?.isEnabled = false

        case .separatingSpeakers(let fraction):
            headerRow?.title = String(localized: "Separating speakers",
                                      comment: "Status bar menu header during diarization")
            detailRow?.isHidden = false
            detailRow?.title = Self.percentage(fraction)
            recordRow?.title = start
            recordRow?.isEnabled = false

        case .done:
            headerRow?.title = String(localized: "Lecture finished", comment: "Status bar menu header after a lecture")
            detailRow?.isHidden = false
            detailRow?.title = String(localized: "\(session.lines.count) lines", comment: "Number of transcript lines so far")
            recordRow?.title = start
            recordRow?.isEnabled = true

        case .failed(let message):
            headerRow?.title = message
            detailRow?.isHidden = true
            recordRow?.title = start
            recordRow?.isEnabled = true
        }
    }

    private static func elapsed(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%02d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
    }

    /// A progress fraction as a percentage. `.percent` rather than a number and
    /// a literal sign so the sign, where it sits and the digits themselves come
    /// from the reader's locale, and so no user-visible text is assembled here.
    private static func percentage(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// The tail of the line being spoken. A menu row cannot grow, so what is
    /// shown is the end of the sentence rather than its beginning — the end is
    /// what is being said right now.
    private static func trimmed(_ text: String, limit: Int = 60) -> String {
        text.count <= limit ? text : "…" + String(text.suffix(limit))
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        Task { @MainActor in
            if session.phase == .recording {
                await session.stop()
            } else {
                await session.start()
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
