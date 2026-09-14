import AppKit

// MARK: - The count

/// How many windows are open, and which of the changes to that number matter.
///
/// A value rather than a counter inside `WindowPresence`, because the rule —
/// the first window raises the policy and the last one drops it — is the part
/// that can be wrong, and asserting it must not mean raising the activation
/// policy of whatever process the assertion is running in.
nonisolated struct WindowTally: Equatable, Sendable {

    private(set) var open = 0

    var hasWindow: Bool { open > 0 }

    /// Returns `true` when this was the first window.
    mutating func opened() -> Bool {
        open += 1
        return open == 1
    }

    /// Returns `true` when this was the last one.
    ///
    /// A close with nothing open is not counted. A window controller that
    /// closes twice would otherwise take the count below zero, and the next
    /// window opened would not be the first.
    mutating func closed() -> Bool {
        guard open > 0 else { return false }
        open -= 1
        return open == 0
    }
}

// MARK: - Applying it

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

    private static var tally = WindowTally()

    static var openWindowCount: Int { tally.open }

    /// Call from a window controller as it shows a window.
    static func opened() {
        guard tally.opened() else { return }
        NSApp.setActivationPolicy(.regular)
        // Raising the policy does not bring the app forward on its own, and a
        // window that opens behind the browser the user was reading is a window
        // they will not find.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call from `windowWillClose`.
    static func closed() {
        guard tally.closed() else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
