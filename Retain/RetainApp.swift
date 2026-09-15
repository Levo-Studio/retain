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

    /// Whether this process is a test host rather than Retain.
    ///
    /// **The tests run inside the real application**, which is what makes them
    /// worth having — they assert the actual launch rather than a
    /// reconstruction of it. The cost is that every test run started a second
    /// Retain: a Dock tile, a status item beside the real one, and an app the
    /// user could not tell from theirs. It was reported three times as "the app
    /// is there twice", and each time it was gone before I looked, because a
    /// test run lasts half a minute.
    ///
    /// Worse than the icons: the host opened the **user's own database** and
    /// swept their audio, because that is what launching does.
    ///
    /// XCTest sets this variable in the environment of the host it launches.
    /// Swift Testing runs inside that host, so it is set for these tests too.
    nonisolated static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// What Retain asks to be. `.regular` for a real launch — an app you cannot
    /// ⌘-Tab to is an app you lose behind a browser — and `.accessory` for a
    /// test host, which has no business in anybody's Dock.
    nonisolated static var activationPolicy: NSApplication.ActivationPolicy {
        isTestHost ? .accessory : .regular
    }

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
        NSApp.setActivationPolicy(Self.activationPolicy)

        // A test host stops here. Everything below opens the user's real
        // database, puts an item in their menu bar and deletes audio off their
        // disk, none of which a test run has any business doing.
        guard !Self.isTestHost else { return }

        // A database that will not open is not a reason to have no status item:
        // the microphone, the live transcript and the window all work without
        // one, and what is lost is that the lecture is written down. The shell
        // carries `nil` in that case rather than refusing to launch.
        let database = try? RetainDatabase.openOnDisk()
        statusItem = StatusItemController(store: database.map(LectureStore.init))

        // A quit or a crash between writing a transcript and deleting the audio
        // it was made from leaves a file that nothing will ever read again.
        // Launch is the only place that is looked for — see `TransientAudio`
        // for why there is no timer — and it happens off the launch path
        // because an interrupted deletion is not a reason to delay the status
        // item appearing.
        // Asked for up front, and loaded if it is cold. The first summary of a
        // lecture used to be what made LM Studio read a 20B model off disk —
        // twenty seconds during which Retain looked like it was doing nothing,
        // and looked exactly the same as a Retain that was never going to
        // answer.
        LanguageModelPresence.shared.refresh()

        if let database {
            Task {
                // A row still claiming to be recording, transcribing or
                // summarising is claiming that a process which no longer
                // exists is working on it. Settled before the sweep, so the
                // sweep sees the states it expects.
                try? await LibraryRepository(database).settleInterruptedRecordings()
                await TransientAudio(database).sweep()
            }
        }
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

    // MARK: - Menu bar

    // Reached through the responder chain from the application menu, so the
    // menu does not have to know where the status item lives.

    @objc func openSettings(_ sender: Any?) {
        statusItem?.showSettingsWindow()
    }

    @objc func openLibrary(_ sender: Any?) {
        statusItem?.showLibraryWindow()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
