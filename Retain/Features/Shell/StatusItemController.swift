import AppKit

/// Owns Retain's entry in the status bar.
///
/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: a `MenuBarExtra` still
/// cannot be opened programmatically, so it cannot be opened by a keyboard
/// shortcut, and Retain's whole point is that you reach it without taking your
/// hands off the keyboard in the middle of a lesson.
@MainActor
final class StatusItemController {

    private let item: NSStatusItem

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
    }

    deinit {
        MainActor.assumeIsolated {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            withTitle: String(localized: "About Retain", comment: "Status bar menu item opening the about panel"),
            action: #selector(showAbout),
            keyEquivalent: ""
        ).target = self

        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "Quit Retain", comment: "Status bar menu item quitting the app"),
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        return menu
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
