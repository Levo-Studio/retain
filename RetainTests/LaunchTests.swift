import AppKit
import Testing

@testable import Retain

/// The tests that would have caught a day-long silent failure.
///
/// `@main` sat on `RetainApp` itself, which conforms to `NSApplicationDelegate`.
/// That synthesises a `main()` calling `NSApplicationMain`, which builds the
/// application and loads the main nib — and it is the nib's File's Owner that
/// sets `NSApp.delegate`. Retain has no nib, so nothing ever set it: the app
/// launched, `pgrep` found it, and `applicationDidFinishLaunching` was never
/// called. No status item, no hotkey, no app.
///
/// Nothing failed. The build was green, the tests were green, and the process
/// was running. That is what makes it worth a test rather than a comment.
///
/// These run inside the real host application, which is started the same way a
/// user's copy is — so they assert the actual launch, not a reconstruction of
/// it.
@Suite("Launch")
@MainActor
struct LaunchTests {

    /// This also covers the second way the same failure happens:
    /// `NSApplication.delegate` is a **weak** reference, so a delegate nothing
    /// else holds is deallocated the moment `main()` returns into `run()` — and
    /// then this is nil rather than wrong.
    @Test("The application has a delegate, it is ours, and it is still alive")
    func delegateIsWired() {
        #expect(NSApp != nil, "there is no application at all")
        #expect(NSApp.delegate is RetainApp, "NSApp.delegate is \(String(describing: NSApp.delegate))")
    }

    @Test("There is a menu bar")
    func mainMenuExists() {
        // Without a nib there is no menu bar unless one is built by hand, and
        // its absence is invisible until a user presses ⌘Q or ⌘V.
        #expect(NSApp.mainMenu != nil)
        #expect((NSApp.mainMenu?.items.count ?? 0) >= 3)
    }

    /// `NSTextField` implements none of these itself — it inherits them from
    /// the responder chain, and the shortcuts only arrive if a menu item claims
    /// them. Without the Edit menu every field in Settings and every dialog
    /// refuses ⌘C and ⌘V with no sign of why.
    @Test("The Edit menu carries the shortcuts a text field depends on")
    func editMenuHasTheStandardActions() throws {
        let menu = RetainMainMenu.make()
        let edit = try #require(
            menu.items.compactMap(\.submenu).first { submenu in
                submenu.items.contains { $0.action == #selector(NSText.paste(_:)) }
            },
            "no Edit menu"
        )

        let expected: [(Selector, String)] = [
            (#selector(NSText.cut(_:)), "x"),
            (#selector(NSText.copy(_:)), "c"),
            (#selector(NSText.paste(_:)), "v"),
            (#selector(NSText.selectAll(_:)), "a"),
        ]

        for (action, key) in expected {
            let item = try #require(edit.items.first { $0.action == action }, "missing \(action)")
            #expect(item.keyEquivalent == key)
            // A nil target sends the action down the responder chain, which is
            // what puts it in the hands of whichever field is first responder.
            // Pointing it anywhere in particular greys it out everywhere.
            #expect(item.target == nil, "\(action) is bound to a target and will be disabled")
        }
    }

    @Test("Quit is reachable from the keyboard")
    func quitExists() throws {
        let menu = RetainMainMenu.make()
        let application = try #require(menu.items.first?.submenu)
        let quit = try #require(
            application.items.first { $0.action == #selector(NSApplication.terminate(_:)) }
        )
        #expect(quit.keyEquivalent == "q")
    }

    @Test("Retain is an ordinary app, with a Dock tile")
    func runsAsARegularApp() {
        // Set in applicationDidFinishLaunching, so this is also a second
        // witness that the delegate actually ran.
        //
        // It was `.accessory` until the owner pointed out that an app you
        // cannot ⌘-Tab to is an app you lose behind a browser.
        #expect(NSApp.activationPolicy() == .regular)
    }
}

// MARK: -

/// The menu bar is where a macOS user looks first, and both of these were only
/// in the status item's right-click menu — a place nobody finds by accident.
/// The owner asked where terms are created; the answer was four clicks behind a
/// gesture that was never mentioned.
@Suite("Application menu")
@MainActor
struct ApplicationMenuTests {

    private func applicationMenu() throws -> NSMenu {
        try #require(RetainMainMenu.make().items.first?.submenu)
    }

    @Test("Settings is in the application menu, on ⌘,")
    func settingsIsReachable() throws {
        let item = try #require(
            applicationMenu().items.first { $0.action == #selector(RetainApp.openSettings(_:)) }
        )
        #expect(item.keyEquivalent == ",")
        #expect(item.keyEquivalentModifierMask == [.command])
        // A nil target sends it down the responder chain to the delegate, which
        // is what lets the menu work without knowing where the status item is.
        #expect(item.target == nil)
    }

    @Test("So is the library")
    func libraryIsReachable() throws {
        let item = try #require(
            applicationMenu().items.first { $0.action == #selector(RetainApp.openLibrary(_:)) }
        )
        #expect(item.keyEquivalent == "l")
        #expect(item.target == nil)
    }

    /// Both are handled by the delegate. A selector the delegate does not
    /// implement leaves the item permanently greyed out, which looks exactly
    /// like the bug this replaced.
    @Test("The delegate answers both")
    func delegateImplementsThem() {
        #expect(RetainApp.instancesRespond(to: #selector(RetainApp.openSettings(_:))))
        #expect(RetainApp.instancesRespond(to: #selector(RetainApp.openLibrary(_:))))
    }
}
