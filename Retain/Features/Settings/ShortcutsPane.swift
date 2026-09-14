import KeyboardShortcuts
import SwiftUI

/// The Shortcuts section: the two hotkeys the design gives, re-bindable.
///
/// `KeyboardShortcuts.Recorder` draws its own control and it is not one the
/// export drew — there is no recorder anywhere on the seven boards. It is used
/// anyway, because it is the control that knows how to catch a key combination
/// safely, and a hand-drawn one would have to re-implement conflict detection
/// and the system's own reserved shortcuts.
struct ShortcutsPane: View {

    var body: some View {
        SettingsPaneSection(
            section: .shortcuts,
            title: String(localized: "Shortcuts", comment: "Settings section heading and sidebar row"),
            description: String(
                localized: "Both work while Retain is in the background, so they reach a recording without leaving the lecture.",
                comment: "Settings section description under the shortcuts heading"
            )
        ) {
            SettingsForm {
                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Note", comment: "Settings field label for the annotation hotkey")
                    )
                    recorder(for: .annotate)
                }

                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Resume", comment: "Settings field label for the resume hotkey")
                    )
                    recorder(for: .resumeRecording)
                }
            }
        }
    }

    private func recorder(for name: KeyboardShortcuts.Name) -> some View {
        KeyboardShortcuts.Recorder(for: name)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
