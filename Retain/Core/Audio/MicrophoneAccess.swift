import AppKit
import AVFoundation

/// Whether Retain may use the microphone.
enum MicrophoneAuthorization: Sendable {

    /// Never asked. The permission dialog on design board 07 is what comes
    /// next, and the system sheet after it.
    case undetermined

    case granted

    /// Refused, or barred by a policy the user cannot lift themselves. Both end
    /// in the same place — Settings — so they are one case here.
    case denied

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .undetermined
        case .denied, .restricted: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// The microphone permission, and nothing else.
///
/// Kept apart from the engine so that Settings can show the state without
/// starting anything, and so that the one place that can raise a system dialog
/// is a single call rather than a side effect of recording.
enum MicrophoneAccess {

    static var authorization: MicrophoneAuthorization {
        MicrophoneAuthorization(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    /// Asks, if it has not been asked before, and answers with the state
    /// afterwards.
    ///
    /// Asking a second time after a refusal does nothing at all — macOS returns
    /// the old answer without showing anything — so a caller that gets `.denied`
    /// has to send the user to System Settings rather than ask again.
    static func request() async -> MicrophoneAuthorization {
        guard authorization == .undetermined else { return authorization }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return authorization
    }

    /// Opens the Privacy pane at Microphone, for the case above.
    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}