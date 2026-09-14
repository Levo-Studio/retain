import Testing

@testable import Retain

/// Retain sits in the status bar as an accessory app and becomes an ordinary
/// one while it has a window open. Getting the count wrong leaves it stuck in
/// one of the two: a Dock tile that never goes away, or a window that cannot be
/// reached with ⌘-Tab and has no menu bar.
///
/// The tally is asserted rather than the application: raising the activation
/// policy of the process a test is running in is not a thing a test may do.
@Suite("Window presence")
struct WindowPresenceTests {

    @Test("The first window is the one that matters")
    func firstWindow() {
        var tally = WindowTally()
        let isFirst = tally.opened()
        #expect(isFirst)
        #expect(tally.open == 1)
        #expect(tally.hasWindow)
    }

    @Test("A second window changes nothing")
    func secondWindow() {
        var tally = WindowTally()
        _ = tally.opened()
        let isFirst = tally.opened()
        #expect(!isFirst)
        #expect(tally.open == 2)
    }

    @Test("The last window closing is the one that matters")
    func lastWindow() {
        // The recording window and the library are both open, and closing one
        // of them must not take the menu bar away from the other.
        var tally = WindowTally()
        _ = tally.opened()
        _ = tally.opened()

        let wasLast = tally.closed()
        #expect(!wasLast)
        #expect(tally.hasWindow)

        let nowLast = tally.closed()
        #expect(nowLast)
        #expect(!tally.hasWindow)
    }

    @Test("A close with nothing open does not go negative")
    func unbalancedClose() {
        // A window controller that closes twice would otherwise leave the count
        // below zero, and the next window opened would not be the first.
        var tally = WindowTally()
        let wasLast = tally.closed()
        #expect(!wasLast)
        #expect(tally.open == 0)

        let isFirst = tally.opened()
        #expect(isFirst)
    }
}
