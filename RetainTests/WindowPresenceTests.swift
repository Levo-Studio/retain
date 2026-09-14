import AppKit
import Testing

@testable import Retain

/// Retain sits in the status bar as an accessory app and becomes an ordinary
/// one while it has a window open. Getting the count wrong leaves it stuck in
/// one of the two: a Dock tile that never goes away, or a window that cannot be
/// reached with ⌘-Tab and has no menu bar.
///
/// Serialised, because there is one application and one counter.
@MainActor
@Suite("Window presence", .serialized)
struct WindowPresenceTests {

    /// Puts the app back where it launched, whatever the test did.
    private func restore() {
        while WindowPresence.openWindowCount > 0 {
            WindowPresence.closed()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    @Test("The first window makes Retain an ordinary app")
    func firstWindowRaisesThePolicy() {
        defer { restore() }

        #expect(WindowPresence.openWindowCount == 0)
        WindowPresence.opened()
        #expect(WindowPresence.openWindowCount == 1)
        #expect(NSApp.activationPolicy() == .regular)
    }

    @Test("The last window closing drops it back to the status bar")
    func lastWindowDropsThePolicy() {
        defer { restore() }

        WindowPresence.opened()
        WindowPresence.closed()
        #expect(WindowPresence.openWindowCount == 0)
        #expect(NSApp.activationPolicy() == .accessory)
    }

    @Test("A second window does not drop the policy when the first one closes")
    func twoWindows() {
        defer { restore() }

        // The recording window and the library are both open, and closing one
        // of them must not take the menu bar away from the other.
        WindowPresence.opened()
        WindowPresence.opened()
        WindowPresence.closed()
        #expect(WindowPresence.openWindowCount == 1)
        #expect(NSApp.activationPolicy() == .regular)

        WindowPresence.closed()
        #expect(NSApp.activationPolicy() == .accessory)
    }

    @Test("A close with nothing open does not go negative")
    func unbalancedClose() {
        defer { restore() }

        // A window controller that closes twice would otherwise leave the count
        // below zero, and the next window opened would not raise the policy.
        WindowPresence.closed()
        #expect(WindowPresence.openWindowCount == 0)

        WindowPresence.opened()
        #expect(NSApp.activationPolicy() == .regular)
    }
}
