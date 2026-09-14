import Foundation

/// The two readouts in the microphone section: the level in decibels and the
/// permission state.
enum MicrophoneReadout {

    // MARK: - Level

    /// The export writes "−18 dB" with **U+2212 MINUS SIGN**, not a hyphen.
    ///
    /// It is the character the design draws and the character a proportional
    /// font gives the right width to; a hyphen-minus sits high and short beside
    /// tabular digits and is the kind of detail that makes a readout look
    /// typed rather than drawn.
    static let minusSign = "\u{2212}"

    /// "−18 dB", from a level's RMS in dBFS.
    ///
    /// Whole decibels: the export draws no fraction, and a meter that shows
    /// tenths is a meter whose last digit never stops moving.
    static func decibels(_ level: AudioLevel) -> String {
        let whole = Int(Double(level.rms).rounded())
        let magnitude = abs(whole).formatted(.number.grouping(.never))
        let signed = whole < 0 ? minusSign + magnitude : magnitude
        return String(localized: "\(signed) dB", comment: "Microphone level readout in settings")
    }

    // MARK: - Permission

    /// What the permission row says.
    ///
    /// Only `granted` is drawn — board 06 shows "erteilt" and nothing else — so
    /// the other two lines are invented.
    static func permission(_ authorization: MicrophoneAuthorization) -> String {
        switch authorization {
        case .granted:
            String(localized: "granted", comment: "Microphone permission state in settings")
        case .undetermined:
            String(localized: "not asked for yet",
                   comment: "Microphone permission state in settings, before the system dialog has been shown")
        case .denied:
            String(localized: "denied",
                   comment: "Microphone permission state in settings, after the user refused")
        }
    }

    /// The button beside that line, where there is one to press.
    ///
    /// Asking a second time after a refusal does nothing at all on macOS — the
    /// system returns the old answer without showing anything — so a refusal
    /// offers System Settings instead of an ask that would look broken.
    enum Remedy: Equatable, Sendable {
        case ask
        case openSystemSettings
    }

    static func remedy(_ authorization: MicrophoneAuthorization) -> Remedy? {
        switch authorization {
        case .granted: nil
        case .undetermined: .ask
        case .denied: .openSystemSettings
        }
    }

    static func remedyTitle(_ remedy: Remedy) -> String {
        switch remedy {
        case .ask:
            String(localized: "Allow access", comment: "Button that raises the microphone permission dialog")
        case .openSystemSettings:
            String(localized: "Open System Settings",
                   comment: "Button that opens the Privacy pane after the microphone was refused")
        }
    }

    // MARK: - Input list

    /// What the input picker says when Core Audio reports no input at all.
    ///
    /// Not drawn: the export draws a Mac with its built-in microphone, which
    /// always has one. A Mac mini with nothing plugged in does not.
    static var noInputDevices: String {
        String(localized: "No microphone found",
               comment: "Input picker label when the Mac has no audio input at all")
    }

    /// The row that means "whatever macOS is using".
    static var systemDefaultInput: String {
        String(localized: "System default", comment: "Input picker row that follows the system default device")
    }
}
