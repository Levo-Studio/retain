import AppKit
import SwiftUI

/// The window board 06 is drawn in.
///
/// An `NSWindow` hosting SwiftUI rather than a SwiftUI `Settings` scene: Retain
/// has no scene graph — the entry point is an `NSApplicationDelegate`, because
/// the shell is a status item and a panel — and `Settings` would drag one in
/// along with a system-drawn preferences chrome the export does not have.
///
/// The title bar is transparent and the content runs the full height, so the
/// strip the board draws is what is seen. The **system's** traffic lights stay,
/// though: the export paints them as three flat grey circles, which is exactly
/// what macOS draws for a window that is not frontmost, and buttons that close
/// the window are better than a drawing of buttons that do not.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
    }

    // MARK: -

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(model: model, drawsTrafficLights: false))

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true

        // Dark only. The export has no light board, so there is no light
        // appearance to follow the system into.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(RetainPalette.surfaceWindow)

        window.setContentSize(RetainMetrics.detailWindowSize)
        window.contentMinSize = RetainMetrics.windowMinimumSize
        window.center()
        window.delegate = self

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Whatever is in the API key field is written before the window goes,
        // and the draft goes with it.
        model.commitAPIKey()
        window = nil
    }
}
