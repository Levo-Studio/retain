import AppKit

/// Retain has no window at launch and, in the finished app, no window at all
/// unless the user asks for one. The entry point is therefore an AppKit
/// delegate rather than a SwiftUI `App`: the shell is an `NSStatusItem` and an
/// `NSPanel`, and a SwiftUI scene graph on top of that would only be something
/// to fight. SwiftUI still draws everything inside the panel and the windows,
/// hosted from here downwards.
@main
final class RetainApp: NSObject, NSApplicationDelegate {

    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory, not regular: no Dock tile and no menu bar of our own while
        // Retain is only sitting in the status bar. Phase 6 raises this to
        // `.regular` for as long as a real window is open, so a recording or
        // the library behaves like an ordinary app, and drops back when the
        // last one closes.
        NSApp.setActivationPolicy(.accessory)

        statusItem = StatusItemController()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
