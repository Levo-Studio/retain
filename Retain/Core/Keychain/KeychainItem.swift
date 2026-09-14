import Foundation
import Security

/// One generic-password item in the keychain, addressed by service and account.
///
/// A value type with no state of its own: every call goes to the keychain, and
/// nothing is cached in memory for longer than the call that reads it. Caching
/// a secret in a property is how it ends up in a crash log.
nonisolated struct KeychainItem: Hashable, Sendable {

    let service: String
    let account: String

    /// The attributes every query shares.
    ///
    /// `kSecAttrSynchronizable: false` keeps the item out of iCloud Keychain.
    /// It is already the default, and it is written out anyway, because a
    /// default that silently changed would put a user's key on Apple's servers
    /// and nothing in the code would look wrong.
    ///
    /// **`kSecUseDataProtectionKeychain` is deliberately not set.** The modern
    /// keychain is the better of the two everywhere it is available, and it is
    /// not available here: it requires an `application-identifier` or
    /// `keychain-access-groups` entitlement, which come from a provisioning
    /// profile. Retain ships Developer ID signed and notarised, with no profile
    /// and no sandbox, so every `Security` call would return
    /// `errSecMissingEntitlement` (-34018) — in the tests and, more to the
    /// point, on a user's Mac. Asking for it and failing is not more secure
    /// than not asking for it.
    private var query: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
    }

    // MARK: - Reading

    /// The stored value, or `nil` if nothing is stored.
    ///
    /// "Nothing is stored" is not an error. LM Studio does not require a key,
    /// the settings field says "leave empty for LM Studio", and an empty field
    /// is the expected state for most users.
    func read() throws -> String? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.unexpectedData }
            guard let text = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return text
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.from(status)
        }
    }

    // MARK: - Writing

    /// Stores `value`, replacing whatever was there.
    ///
    /// An empty or whitespace-only value deletes the item instead of storing
    /// it. Clearing the settings field means "there is no key", and an item
    /// holding an empty string would then be sent as an `Authorization` header
    /// with nothing behind it.
    func write(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete()
            return
        }

        guard let data = trimmed.data(using: .utf8) else { throw KeychainError.unexpectedData }

        // Update before add, rather than delete before add: updating leaves the
        // item's access control alone, where deleting and re-adding hands the
        // new item whatever ACL the current process happens to imply.
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError.from(updated) }

        var addition = query
        addition[kSecValueData] = data
        addition[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let added = SecItemAdd(addition as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError.from(added) }
    }

    /// Removes the item. Removing one that is not there succeeds.
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.from(status)
        }
    }
}

// MARK: - The items Retain keeps

/// Every keychain item Retain owns.
///
/// There is exactly one, and there is expected to be exactly one: Retain has no
/// account, talks to no service but `localhost`, and has nothing else to keep
/// secret.
nonisolated enum RetainKeychain {

    /// Matches the bundle identifier so the item is recognisable in Keychain
    /// Access and so a user who wants it gone can find it.
    static let service = "apps.levo-studio.Retain"

    /// The optional API key for the local LM Studio server.
    ///
    /// Hard rule 10: this never goes in `UserDefaults`, even though the server
    /// is on `localhost`. `UserDefaults` is a world-readable plist in the
    /// user's Library, and a key that guards nothing today guards something the
    /// day the user points Retain at a server that checks it.
    static let languageModelAPIKey = KeychainItem(service: service, account: "language-model-api-key")
}
