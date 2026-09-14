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

/// Brings Retain forward when its first window opens, and keeps count of how
/// many are open.
///
/// This used to switch the activation policy as well: Retain launched as an
/// accessory and became an ordinary app only while a window happened to be
/// open. That is gone — Retain is a regular app now, because an accessory's
/// windows cannot be reached with ⌘-Tab, do not appear in Mission Control, and
/// once something covers them there is no way back except through the status
/// item. Making all of that depend on state the user cannot see was worse than
/// either answer on its own.
///
/// What is left is the part that was always needed: opening a window does not
/// bring the app forward on its own, and a window that appears behind the
/// browser somebody was reading is a window they will not find.
///
/// Counted rather than toggled, because there is more than one window — the
/// recording, a recording's detail, the library, Settings.
@MainActor
enum WindowPresence {

    private static var tally = WindowTally()

    static var openWindowCount: Int { tally.open }

    /// Call from a window controller as it shows a window.
    static func opened() {
        guard tally.opened() else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call from `windowWillClose`.
    static func closed() {
        _ = tally.closed()
    }
}
