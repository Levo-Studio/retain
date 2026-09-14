import AppKit

/// Retain's menu bar.
///
/// Built in code because there is no nib — see `RetainMain`. It is short on
/// purpose: an accessory app's menu bar is only visible while one of its
/// windows is frontmost, so this is not a place to put features. What it has to
/// carry is the set of things macOS users reach for without looking, and that
/// every `NSTextField` silently depends on.
///
/// **The Edit menu is the one that matters.** `NSTextField` does not implement
/// copy, paste, cut or select-all itself — it inherits them from the responder
/// chain, and the shortcuts only arrive if a menu item claims them. Without
/// this menu, every field in Settings and every dialog would refuse ⌘C and ⌘V
/// with no sign of why.
@MainActor
enum RetainMainMenu {

    static func make() -> NSMenu {
        let bar = NSMenu()
        bar.addItem(applicationMenuItem())
        bar.addItem(editMenuItem())
        bar.addItem(windowMenuItem())
        return bar
    }

    // MARK: - Retain

    private static func applicationMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(
            withTitle: String(localized: "About Retain", comment: "Application menu item opening the about panel"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())

        let hide = menu.addItem(
            withTitle: String(localized: "Hide Retain", comment: "Application menu item hiding the app"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hide.target = NSApp

        let hideOthers = menu.addItem(
            withTitle: String(localized: "Hide Others", comment: "Application menu item hiding other apps"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp

        menu.addItem(.separator())

        let quit = menu.addItem(
            withTitle: String(localized: "Quit Retain", comment: "Application menu item quitting the app"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp

        item.submenu = menu
        return item
    }

    // MARK: - Edit

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Edit", comment: "Edit menu title"))

        // No targets on any of these: a nil target sends the action down the
        // responder chain, which is what puts it in the hands of whichever text
        // field is first responder. Pointing them at anything in particular is
        // how these end up greyed out everywhere.
        menu.addItem(
            withTitle: String(localized: "Undo", comment: "Edit menu item"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redo = menu.addItem(
            withTitle: String(localized: "Redo", comment: "Edit menu item"),
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "Cut", comment: "Edit menu item"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        menu.addItem(
            withTitle: String(localized: "Copy", comment: "Edit menu item"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        menu.addItem(
            withTitle: String(localized: "Paste", comment: "Edit menu item"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        menu.addItem(
            withTitle: String(localized: "Select All", comment: "Edit menu item"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        item.submenu = menu
        return item
    }

    // MARK: - Window

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Window", comment: "Window menu title"))

        menu.addItem(
            withTitle: String(localized: "Close", comment: "Window menu item closing the front window"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        menu.addItem(
            withTitle: String(localized: "Minimise", comment: "Window menu item minimising the front window"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )

        item.submenu = menu
        // Handing the menu to AppKit is what makes it list the open windows and
        // keep the tick beside the frontmost one.
        NSApp.windowsMenu = menu
        return item
    }
}
