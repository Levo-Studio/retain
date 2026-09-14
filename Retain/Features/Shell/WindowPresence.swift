import AppKit

/// Raises Retain to an ordinary app while it has a window open, and drops it
/// back to the status bar when the last one closes.
///
/// Retain launches as an accessory: no Dock tile, no menu bar, nothing but the
/// status item. That is right while it is only sitting there, and wrong the
/// moment a real window is on screen — an accessory app's windows cannot be
/// reached with ⌘-Tab, have no menu bar to hold Copy or Close, and cannot be
/// brought forward once something covers them.
///
/// Counted rather than toggled, because there will be more than one window —
/// the recording, the lesson detail, the library, Settings — and the last one
/// to close is the one that decides.
@MainActor
enum WindowPresence {

    private static var open = 0

    /// Call from a window controller as it shows a window.
    static func opened() {
        open += 1
        guard open == 1 else { return }
        NSApp.setActivationPolicy(.regular)
        // Raising the policy does not bring the app forward on its own, and a
        // window that opens behind the browser the user was reading is a window
        // they will not find.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call from `windowWillClose`.
    static func closed() {
        open = max(0, open - 1)
        guard open == 0 else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// How many windows are open. For tests, and for anything that needs to
    /// know whether Retain currently has a menu bar.
    static var openWindowCount: Int { open }
}
