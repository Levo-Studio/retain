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
        // Accessory, not regular: no Dock tile while Retain is only sitting in
        // the status bar. `WindowPresence` raises it to `.regular` for as long
        // as a real window is open, so a recording or the library behaves like
        // an ordinary app, and drops it back when the last one closes.
        NSApp.setActivationPolicy(.accessory)

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

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
