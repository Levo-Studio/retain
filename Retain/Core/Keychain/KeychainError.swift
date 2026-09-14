import Foundation
import Security

/// What can go wrong talking to the keychain.
///
/// Every case carries a sentence a user can act on. The raw `OSStatus` is kept
/// only on `unhandled`, because that is the one case where the number is the
/// only information there is.
nonisolated enum KeychainError: Error, Equatable, LocalizedError {

    /// An item came back that is not UTF-8 text. Something other than Retain
    /// wrote to this account.
    case unexpectedData

    /// `errSecMissingEntitlement`. The process has no keychain access group,
    /// which means it is not signed the way it was shipped.
    case missingEntitlement

    /// The keychain is locked or the user refused the access dialog.
    case accessDenied

    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            String(localized: "The keychain holds something Retain cannot read as an API key.",
                   comment: "Keychain item exists but is not text")
        case .missingEntitlement:
            String(localized: "Retain is not allowed to use the keychain. Reinstalling Retain fixes this.",
                   comment: "Keychain refused the app because it is not signed correctly")
        case .accessDenied:
            String(localized: "Retain was refused access to the keychain.",
                   comment: "Keychain is locked or the user denied the access dialog")
        case .unhandled(let status):
            String(localized: "Retain could not use the keychain. (\(status))",
                   comment: "Keychain failed with an OSStatus Retain has no specific message for")
        }
    }

    /// Maps a raw status onto the cases above. `errSecSuccess` and
    /// `errSecItemNotFound` are not errors here — a key that was never set is
    /// the normal state, since LM Studio does not require one.
    static func from(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecMissingEntitlement:
            .missingEntitlement
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            .accessDenied
        default:
            .unhandled(status)
        }
    }
}
