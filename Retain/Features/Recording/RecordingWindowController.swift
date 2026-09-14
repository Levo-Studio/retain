import AppKit
import SwiftUI

/// The window board 01 is drawn in.
///
/// An ordinary window with traffic lights, unlike the popover — it is where the
/// lecture is watched for an hour, and it has to behave like every other window
/// on the machine. The title bar is Retain's own, drawn 38 points tall with the
/// meter and the timer in it, so the system's is made transparent and the
/// content runs under it.
@MainActor
final class RecordingWindowController: NSObject, NSWindowDelegate {

    private let shell: ShellModel
    private var window: NSWindow?

    var isOpen: Bool { window?.isVisible == true }

    init(shell: ShellModel) {
        self.shell = shell
    }

    // MARK: - Showing it

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        let wasOpen = window.isVisible
        window.makeKeyAndOrderFront(nil)
        if !wasOpen {
            WindowPresence.opened()
            window.center()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeWindow() -> NSWindow {
        let size = RetainMetrics.recordingWindowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = String(localized: "Recording", comment: "Title of the recording window")
        // The design's title bar is drawn by the app, so the system's carries
        // nothing but the traffic lights and lets the content through.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(RetainPalette.surfaceWindow)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RecordingRoot(shell: shell))
        window.setContentSize(size)

        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        WindowPresence.closed()
    }
}
