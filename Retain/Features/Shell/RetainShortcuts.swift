import AppKit
import KeyboardShortcuts

/// Retain's global shortcuts.
///
/// Global, not window-local, and that is the whole reason the shell is an
/// `NSStatusItem` and an `NSPanel`: a lecture is recorded while the user is in
/// a browser, a PDF and a text editor, and the shortcut that marks the sentence
/// the teacher just said has to work from all three.
///
/// Two of the three are drawn. `⌘⇧M` is on board 01, in the annotation bar, and
/// `⌘⇧P` is on board 02, under the paused state. **The shortcut that opens the
/// popover is not drawn anywhere** — board 06's Shortcuts section is a list
/// nothing on the boards spells out — so `⌘⇧R` is a choice and not a reading.
nonisolated extension KeyboardShortcuts.Name {

    /// Opens the popover, or closes it if it is already open.
    static let togglePopover = Self("togglePopover", initial: .init(.r, modifiers: [.command, .shift]))

    /// Puts the caret in the annotation composer — of the recording window if
    /// it is open, and of the popover otherwise.
    static let annotate = Self("annotate", initial: .init(.m, modifiers: [.command, .shift]))

    /// Continues a paused recording.
    static let resumeRecording = Self("resumeRecording", initial: .init(.p, modifiers: [.command, .shift]))
}
