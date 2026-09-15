import Defaults
import Foundation

/// The LM Studio API key, read from the Keychain once per launch.
///
/// **This exists because a Keychain read is not free.** It used to be read on
/// every request, on the reasoning that a secret with a lifetime of one request
/// should not sit in a property. What that ignored is that macOS decides
/// whether a process may read an item by comparing the process's code signature
/// against the one recorded on the item — and when they do not match it asks
/// the user. Retain reads the key for the model list, again for the connection
/// test, and again for every block it summarises, so a lecture turned into a
/// queue of identical password sheets. Allowing one did not help: the next read
/// asked again.
///
/// The signatures stop disagreeing once Retain is signed with its Developer ID
/// and that signature stays put from build to build. Until then, and after,
/// reading once per launch is the right number of times: the user is asked at
/// most once, and the key still has to be in memory to be put in a header.
///
/// The cache is dropped when Settings writes a new key, so a replaced key takes
/// effect on the next request rather than at the next launch.
nonisolated final class LanguageModelKey: @unchecked Sendable {

    static let shared = LanguageModelKey()

    private let item: KeychainItem
    private let lock = NSLock()

    /// `nil` means "not read yet". `.some(nil)` means "read, and there is no
    /// key" — which is the ordinary state, since LM Studio does not require
    /// one, and which must not send us back to the Keychain every request.
    private var cached: String??

    init(item: KeychainItem = RetainKeychain.languageModelAPIKey) {
        self.item = item
    }

    /// The key, reading it the first time and remembering the answer.
    ///
    /// **The Keychain is not touched at all when nothing was ever stored.** LM
    /// Studio needs no key, which makes "no key" the ordinary case — and a read
    /// of an item this binary is not recognised as entitled to read puts a
    /// password sheet on screen. Asking the user for a password to fetch a
    /// secret that does not exist is the worst version of that, and it happened
    /// at every launch.
    func value() -> String? {
        guard Defaults[.hasLanguageModelKey] else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }
        let read = try? item.read()
        cached = .some(read)
        return read
    }

    /// Records a key that has just been written, without going back to the
    /// Keychain for it.
    func replace(with key: String?) {
        lock.lock()
        defer { lock.unlock() }
        cached = .some(key)
    }

    /// Forgets what was read. The next request asks the Keychain again.
    func forget() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }

    /// Writes a key and keeps the cache in step, in one place.
    ///
    /// **Every touch of the item goes through here.** Settings used to read it
    /// with its own `KeychainItem` while the backend read it through this
    /// cache, so opening the pane cost a second access — and on a build whose
    /// signature the item does not recognise, each access is its own password
    /// sheet. One launch could ask three times.
    func write(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Unconditionally, even when the flag says there is nothing: an
            // item left by an earlier version has to be reachable by the one
            // action that removes it.
            try item.delete()
            replace(with: nil)
        } else {
            try item.write(trimmed)
            replace(with: trimmed)
        }
        Defaults[.hasLanguageModelKey] = !trimmed.isEmpty
    }
}
