import AppKit
import Defaults
import Foundation
import KeyboardShortcuts

// MARK: - Stored settings

/// What the settings window remembers between launches.
///
/// **The API key is not here, and never will be.** Hard rule 10: it lives in
/// the Keychain, even though the server is on `localhost`, because
/// `UserDefaults` is a plist in the user's Library that any process running as
/// them can read.
extension Defaults.Keys {

    /// The Base URL field. It holds `…/v1` and keeps holding it — the client
    /// swaps the path to `/api/v0/` in `LMStudioEndpoint`, and the stored value
    /// is the one the user typed.
    static let languageModelAddress = Key<String>(
        "languageModelAddress",
        default: LMStudioEndpoint.defaultBaseAddress
    )

    /// The model id the picker last settled on. Empty until the server has been
    /// asked what it has.
    static let languageModelName = Key<String>("languageModelName", default: "")

    /// The microphone, by the UID that survives a reboot. `nil` follows
    /// whatever macOS is using, which is what a user who plugs in a headset
    /// expects.
    static let preferredInputDeviceUID = Key<String?>("preferredInputDeviceUID")

    /// Which pane the window opens on. The board draws Language model selected,
    /// but the pane somebody was last in is the one they want next.
    static let settingsSection = Key<SettingsSection>("settingsSection", default: .languageModel)
}

extension SettingsSection: Defaults.Serializable {}

// MARK: - Shortcuts

/// The two hotkeys the design gives, by the names `KeyboardShortcuts` stores
/// them under.
///
/// Defined here because the Shortcuts pane is where they are re-bound. They are
/// app-wide, not settings-wide: the annotation hotkey is caught during a
/// recording and the resume hotkey while one is paused, both from the shell.
extension KeyboardShortcuts.Name {

    /// `⌘⇧M` — types an annotation that goes to the model and comes back out in
    /// the notes as "You · 00:46:41".
    static let annotate = Self("annotate", initial: .init(.m, modifiers: [.command, .shift]))

    /// `⌘⇧P` — resumes a paused recording, as board 02 says it does.
    static let resumeRecording = Self("resumeRecording", initial: .init(.p, modifiers: [.command, .shift]))
}
