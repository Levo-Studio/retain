import AppKit

/// The process entry point.
///
/// **`@main` does not belong on the delegate, and putting it there is a silent
/// failure.** `@main` on a type conforming to `NSApplicationDelegate`
/// synthesises a `main()` that calls `NSApplicationMain`, which builds the
/// application and then loads the main nib — and it is the nib's File's Owner
/// that sets `NSApp.delegate`. Retain has no nib. So the app launched, the
/// process appeared in `pgrep`, and `applicationDidFinishLaunching` was never
/// called: no status item, no hotkey, no app. It cost a day, because a process
/// that is running looks exactly like a process that is working.
///
/// Starting the application by hand is three lines and leaves nothing implicit.
@main
@MainActor
enum RetainMain {

    /// `NSApplication.delegate` is a weak reference. Without a strong one here
    /// the delegate is deallocated the moment `main()` returns into `run()`,
    /// which is the same failure again with a different cause.
    private static var delegate: RetainApp?

    static func main() {
        let application = NSApplication.shared

        let delegate = RetainApp()
        Self.delegate = delegate
        application.delegate = delegate

        // Without a nib there is no menu bar either, and that is not only a
        // missing Quit: an `NSTextField` gets copy, paste and select-all from
        // the Edit menu, so a window with a text field in it and no main menu
        // has fields the standard shortcuts do not work in.
        application.mainMenu = RetainMainMenu.make()

        application.run()
    }
}

// MARK: -

/// What Retain does when it starts, and the policy it runs under.
final class RetainApp: NSObject, NSApplicationDelegate {

    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An ordinary app with a Dock tile, not an accessory.
        //
        // Retain started as an accessory — it is a status-bar app, and an app
        // with nothing but a status item has no business in the Dock. The
        // trouble is that it does not have nothing but a status item: there is
        // a recording window, a library, a detail window per recording, and
        // Settings. An accessory's windows cannot be reached with ⌘-Tab, do not
        // appear in Mission Control, and once something covers them there is no
        // way back except through the status item. Raising the policy only
        // while a window happened to be open made all of that conditional on
        // state the user cannot see, which is worse than either answer alone.
        NSApp.setActivationPolicy(.regular)

        // A database that will not open is not a reason to have no status item:
        // the microphone, the live transcript and the window all work without
        // one, and what is lost is that the lecture is written down. The shell
        // carries `nil` in that case rather than refusing to launch.
        statusItem = StatusItemController(store: (try? RetainDatabase.openOnDisk()).map(LectureStore.init))
    }

    /// Closing the last window puts Retain back in the status bar; it does not
    /// quit it. A lecture can be recording with nothing on screen, and that is
    /// the ordinary case rather than an edge one.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock tile with no window open.
    ///
    /// Without this the click does nothing at all, which reads as a hang. The
    /// library is the right answer rather than the recording window: it is
    /// where everything already recorded is, and starting a recording is what
    /// the status item is for.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        statusItem?.showLibraryWindow()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
