import Foundation
import Security
import Testing

@testable import Retain

/// The keychain, for real.
///
/// The test target is ad-hoc signed on purpose — see the toolchain note in
/// `CLAUDE.md`. An unsigned process has no keychain access group, every
/// `Security` call returns `errSecMissingEntitlement` before it reaches any
/// Retain code, and a test suite that "passes" because nothing ran is worse
/// than no suite at all.
///
/// Every test uses a service name of its own and deletes the item before and
/// after it runs. Two reasons: nothing is left behind in the developer's
/// keychain, and the item is always created by the process that then reads it,
/// which is what keeps macOS from putting an access dialog in front of a test
/// run and waiting for somebody to click it.
@Suite("Keychain", .serialized)
struct KeychainTests {

    private func scratch(_ name: String = #function) -> KeychainItem {
        KeychainItem(service: "apps.levo-studio.Retain.tests.\(name)", account: "language-model-api-key")
    }

    @Test("Nothing stored is not an error")
    func missingItemReadsAsNil() throws {
        let item = scratch()
        try item.delete()
        #expect(try item.read() == nil)
    }

    @Test("What goes in comes back out")
    func roundTrip() throws {
        let item = scratch()
        try item.delete()
        defer { try? item.delete() }

        try item.write("lm-studio-key-äöü")
        #expect(try item.read() == "lm-studio-key-äöü")
    }

    @Test("Writing twice replaces rather than duplicates")
    func writingTwiceReplaces() throws {
        let item = scratch()
        try item.delete()
        defer { try? item.delete() }

        try item.write("erster")
        try item.write("zweiter")
        #expect(try item.read() == "zweiter")
    }

    /// Clearing the settings field means "there is no key". An item holding an
    /// empty string would otherwise be sent as a bearer token with nothing
    /// behind it.
    @Test("An empty value removes the item instead of storing it")
    func emptyValueDeletes() throws {
        let item = scratch()
        defer { try? item.delete() }

        try item.write("etwas")
        try item.write("   ")
        #expect(try item.read() == nil)
    }

    @Test("Surrounding whitespace is not part of the key")
    func valuesAreTrimmed() throws {
        let item = scratch()
        try item.delete()
        defer { try? item.delete() }

        try item.write("  lm-studio-key  ")
        #expect(try item.read() == "lm-studio-key")
    }

    @Test("Deleting something that is not there succeeds")
    func deletingTwiceSucceeds() throws {
        let item = scratch()
        try item.delete()
        try item.delete()
    }

    @Test("Two accounts do not see each other")
    func itemsAreSeparate() throws {
        let service = "apps.levo-studio.Retain.tests.separate"
        let first = KeychainItem(service: service, account: "one")
        let second = KeychainItem(service: service, account: "two")
        defer {
            try? first.delete()
            try? second.delete()
        }

        try first.write("eins")
        try second.write("zwei")

        #expect(try first.read() == "eins")
        #expect(try second.read() == "zwei")
    }

    /// Hard rule 10, as an address rather than a behaviour: the key is a
    /// keychain item, and it is not, anywhere, a `UserDefaults` value.
    @Test("The API key has one home and it is the keychain")
    func theKeyLivesInTheKeychain() {
        #expect(RetainKeychain.languageModelAPIKey.service == "apps.levo-studio.Retain")
        #expect(RetainKeychain.languageModelAPIKey.account == "language-model-api-key")
        #expect(UserDefaults.standard.object(forKey: "language-model-api-key") == nil)
    }

    @Test("A status the wrapper has no message for still says which one it was")
    func statusesMapToMessages() {
        #expect(KeychainError.from(errSecMissingEntitlement) == .missingEntitlement)
        #expect(KeychainError.from(errSecInteractionNotAllowed) == .accessDenied)
        #expect(KeychainError.from(errSecUserCanceled) == .accessDenied)
        #expect(KeychainError.from(errSecDecode) == .unhandled(errSecDecode))
        #expect(KeychainError.unhandled(errSecDecode).errorDescription?.isEmpty == false)
    }
}
