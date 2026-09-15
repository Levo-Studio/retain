import Foundation
import Testing

@testable import Retain

// MARK: - A backend that answers without a server

/// Answers from what it was handed, so the settings pane can be exercised
/// without LM Studio running anywhere.
nonisolated final class SettingsStubBackend: SummarizationBackend, @unchecked Sendable {

    var models: [LanguageModelDescriptor]
    var report: ConnectionReport?
    var failure: (any Error)?

    init(
        models: [LanguageModelDescriptor] = [],
        report: ConnectionReport? = nil,
        failure: (any Error)? = nil
    ) {
        self.models = models
        self.report = report
        self.failure = failure
    }

    func availableModels() async throws -> [LanguageModelDescriptor] {
        if let failure { throw failure }
        return models
    }

    func loadedContextLength(of model: String) async throws -> Int? { nil }

    /// A stub server has nothing to read off disk, so loading is instant — but
    /// it still fails when the whole backend is failing, because a test that
    /// says "the server is down" means down for this too.
    func load(_ model: String) async throws {
        if let failure { throw failure }
    }

    func checkConnection() async throws -> ConnectionReport {
        if let failure { throw failure }
        return report ?? ConnectionReport(modelCount: models.count, latency: 0)
    }

    func structuredReply<Answer: Decodable & Sendable>(
        to conversation: ChatConversation,
        model: String,
        schema: SchemaDescription,
        as answer: Answer.Type
    ) async throws -> StructuredReply<Answer> {
        throw SummarizationError.unreachable
    }
}

// MARK: -

@Suite("Settings — language model")
struct SettingsLanguageModelTests {

    // MARK: - Base URL

    @Test("The address LM Studio ships with is accepted")
    func defaultAddressIsAccepted() {
        #expect(BaseAddress.isAcceptable(BaseAddress.default))
        #expect(BaseAddress.default == "http://localhost:1234/v1")
    }

    @Test(
        "Every spelling of this Mac is accepted",
        arguments: [
            "http://localhost:1234/v1",
            "http://127.0.0.1:1234/v1",
            "http://[::1]:1234/v1",
            "https://localhost:1234/v1",
            "http://localhost:1234",
            "  http://localhost:1234/v1  ",
        ]
    )
    func localAddressesAreAccepted(_ address: String) {
        #expect(BaseAddress.isAcceptable(address))
    }

    /// Hard rule 9. A base URL that is not this Mac is refused before a socket
    /// is opened, not warned about and then attempted.
    @Test(
        "An address that is not this Mac is refused",
        arguments: [
            "http://192.168.1.10:1234/v1",
            "http://example.com/v1",
            "https://api.openai.com/v1",
            "http://0.0.0.0:1234/v1",
            "http://localhost.evil.com:1234/v1",
            "ftp://localhost:1234/v1",
            "",
            "not a url at all",
        ]
    )
    func remoteAddressesAreRefused(_ address: String) {
        #expect(!BaseAddress.isAcceptable(address))
        #expect(BaseAddress.rejection(for: address) != nil)
    }

    @Test("A refusal says why without naming the address")
    func refusalDoesNotEchoTheAddress() {
        let rejection = BaseAddress.rejection(for: "https://api.openai.com/v1?key=sk-secret")
        #expect(rejection?.isEmpty == false)
        #expect(rejection?.contains("openai") == false)
        #expect(rejection?.contains("sk-secret") == false)
    }

    // MARK: - The status line

    @Test("The connected line reads the way board 06 draws it")
    func connectedLine() {
        let report = ConnectionReport(modelCount: 3, latency: 0.240)
        #expect(
            LanguageModelConnection.connected(report).message
                == "Connected · 3 models loaded · answered in 240 ms"
        )
    }

    @Test("One model is one model")
    func connectedLineIsSingular() {
        let report = ConnectionReport(modelCount: 1, latency: 0.004)
        #expect(
            LanguageModelConnection.connected(report).message
                == "Connected · 1 model loaded · answered in 4 ms"
        )
    }

    @Test("Latency is whole milliseconds")
    func latencyRounds() {
        #expect(LanguageModelConnection.milliseconds(0.2404) == 240)
        #expect(LanguageModelConnection.milliseconds(0.2406) == 241)
        #expect(LanguageModelConnection.milliseconds(0) == 0)
    }

    @Test("An untested connection draws no line at all")
    func untestedDrawsNothing() {
        #expect(LanguageModelConnection.untested.message == nil)
        #expect(!LanguageModelConnection.untested.isGood)
    }

    @Test("A failure says the error's own words")
    func failureCarriesTheMessage() {
        let connection = LanguageModelConnection.failed("LM Studio is not responding.")
        #expect(connection.message == "LM Studio is not responding.")
        #expect(connection.isFailure)
    }

    // MARK: - The model picker

    @Test("A server that lists nothing says so, and the picker will not open")
    func emptyModelList() {
        #expect(ModelPicker.label(selected: "", available: []) == "No models on the server")
        #expect(ModelPicker.label(selected: "qwen3-14b", available: []) == "No models on the server")
        #expect(!ModelPicker.isEnabled(available: []))
        #expect(ModelPicker.isPlaceholder(selected: "qwen3-14b", available: []))
    }

    @Test("A server with models and no choice made asks for one")
    func noSelection() {
        let models = [LanguageModelDescriptor(id: "a", contextLength: nil),
                      LanguageModelDescriptor(id: "b", contextLength: nil)]
        #expect(ModelPicker.label(selected: "", available: models) == "Choose a model")
        #expect(ModelPicker.isEnabled(available: models))
        #expect(ModelPicker.isPlaceholder(selected: "", available: models))
    }

    @Test("A chosen model is drawn as a value")
    func chosenModel() {
        let models = [LanguageModelDescriptor(id: "qwen3-14b-instruct", contextLength: nil)]
        #expect(ModelPicker.label(selected: "qwen3-14b-instruct", available: models) == "qwen3-14b-instruct")
        #expect(!ModelPicker.isPlaceholder(selected: "qwen3-14b-instruct", available: models))
    }

    @Test("A test against a server with no models leaves nothing selected")
    func testingAnEmptyServerClearsTheSelection() async {
        let model = SettingsModel(makeBackend: { _ in SettingsStubBackend(models: []) })
        model.address = BaseAddress.default
        model.selectedModel = "a-model-that-is-gone"

        await model.testConnection()

        #expect(model.availableModels.isEmpty)
        #expect(model.selectedModel.isEmpty)
        #expect(model.connection.isGood)
    }

    @Test("A server with exactly one model needs no decision")
    func oneModelIsAdopted() async {
        let model = SettingsModel(
            makeBackend: { _ in SettingsStubBackend(models: [LanguageModelDescriptor(id: "only", contextLength: nil)]) }
        )
        model.address = BaseAddress.default
        model.selectedModel = ""

        await model.refreshModels()

        #expect(model.selectedModel == "only")
    }

    @Test("A test against an address that is not this Mac never reaches a backend")
    func remoteAddressNeverReachesTheBackend() async {
        var built = false
        let model = SettingsModel(makeBackend: { _ in
            built = true
            return SettingsStubBackend()
        })
        model.address = "https://api.openai.com/v1"

        await model.testConnection()

        #expect(!built)
        #expect(model.connection.isFailure)
    }

    // MARK: - What a failure is allowed to say

    @Test("A refused connection shows the design's sentence, not URLSession's")
    func urlErrorIsTranslated() {
        let message = SettingsModel.message(for: URLError(.cannotConnectToHost))
        #expect(message == "LM Studio is not responding.")
    }

    /// The address field is a field: somebody told to authenticate will paste a
    /// key into it sooner or later. Nothing that reaches the screen may carry
    /// one.
    @Test("No message anywhere carries a key that was pasted into the address")
    func noMessageLeaksAKey() async {
        let secret = "sk-live-0123456789abcdef"
        let address = "https://user:\(secret)@api.openai.com/v1?token=\(secret)"

        let model = SettingsModel(makeBackend: { _ in SettingsStubBackend(failure: URLError(.cannotConnectToHost)) })
        model.address = address
        await model.testConnection()

        #expect(model.connection.message?.contains(secret) == false)
        #expect(model.addressRejection?.contains(secret) == false)
        #expect(!BaseAddress.displayed(address).contains(secret))
    }

    @Test("A displayed address keeps the server and drops the secret")
    func displayedAddressIsStripped() {
        #expect(BaseAddress.displayed("http://localhost:1234/v1") == "http://localhost:1234/v1")
        #expect(
            BaseAddress.displayed("http://user:sk-secret@localhost:1234/v1?key=sk-secret#frag")
                == "http://localhost:1234/v1"
        )
    }

    // MARK: - The API key

    @Test("The placeholder is only ever the empty state, and never a key")
    func placeholderNeverShowsAKey() {
        #expect(APIKeyField.placeholder == "leave empty for LM Studio")
        #expect(!APIKeyField.placeholder.contains("sk-"))
    }

    /// The bug this exists for, reported from the app: a token was pasted into
    /// the field, "Test connection" was pressed, and LM Studio answered that it
    /// requires an API token — the field was still a draft, so the request had
    /// gone out with no `Authorization` header at all, and nothing on screen
    /// said the key had not been taken.
    @Test("Pasting a key stores it there and then")
    func typingStoresImmediately() {
        let item = KeychainItem.forTest("settings-immediate")
        defer { try? item.delete() }
        try? item.delete()

        let model = SettingsModel(keychain: item)
        model.apiKeyDraft = "sk-pasted"

        // No commit, no Return, no closing the window.
        #expect((try? item.read()) == "sk-pasted")
        #expect(model.hasStoredKey)
        #expect(model.apiKeyProblem == nil)
    }

    @Test("A stored key is in the field when the window opens")
    func theStoredKeyIsLoaded() {
        let item = KeychainItem.forTest("settings-loaded")
        defer { try? item.delete() }
        try? item.write("sk-stored")

        let model = SettingsModel(keychain: item)
        model.loadAPIKey()

        // It is drawn as dots by a `SecureField`. A field that shows nothing
        // while a key exists cannot be told apart from one that lost it, which
        // is exactly how the old behaviour was reported.
        #expect(model.apiKeyDraft == "sk-stored")
        #expect(model.hasStoredKey)
    }

    @Test("The field keeps what was typed rather than emptying itself")
    func theFieldIsNotCleared() {
        let item = KeychainItem.forTest("settings-keeps")
        defer { try? item.delete() }
        try? item.delete()

        let model = SettingsModel(keychain: item)
        model.apiKeyDraft = "sk-typed"
        model.commitAPIKey()

        #expect(model.apiKeyDraft == "sk-typed")
        #expect((try? item.read()) == "sk-typed")
    }

    @Test("A key is stored trimmed")
    func theKeyIsTrimmed() {
        let item = KeychainItem.forTest("settings-trimmed")
        defer { try? item.delete() }
        try? item.delete()

        let model = SettingsModel(keychain: item)
        model.apiKeyDraft = "  sk-abc  "

        #expect((try? item.read()) == "sk-abc")
    }

    @Test("Clearing the field removes the item")
    func clearingRemovesTheItem() {
        let item = KeychainItem.forTest("settings-cleared")
        defer { try? item.delete() }
        try? item.write("sk-stored")

        let model = SettingsModel(keychain: item)
        model.loadAPIKey()
        model.apiKeyDraft = ""

        #expect((try? item.read()) == nil)
        #expect(!model.hasStoredKey)
    }

    @Test("A key pasted before the test is the one the test uses")
    func testingUsesThePastedKey() async {
        let item = KeychainItem.forTest("settings-test-uses")
        defer { try? item.delete() }
        try? item.delete()

        let model = SettingsModel(
            keychain: item,
            makeBackend: { _ in SettingsStubBackend(models: []) }
        )
        model.apiKeyDraft = "sk-pasted"
        await model.testConnection()

        #expect((try? item.read()) == "sk-pasted")
        #expect(model.hasStoredKey)
    }

    /// The bug that hung the test host for five and a half minutes: the model
    /// is built while the app is launching, and it used to read the Keychain
    /// right there. A build whose signature the stored item does not recognise
    /// gets a system password sheet for that read — in front of an app that has
    /// not finished starting, which is a hang with nothing on screen to explain
    /// it.
    @Test("Building the model does not touch the Keychain")
    func theKeychainIsNotReadAtLaunch() {
        let item = KeychainItem.forTest("settings-not-at-launch")
        defer { try? item.delete() }
        try? item.write("sk-stored")

        let model = SettingsModel(keychain: item)

        #expect(model.apiKeyDraft.isEmpty)
        #expect(!model.hasStoredKey)

        model.loadAPIKey()
        #expect(model.apiKeyDraft == "sk-stored")
    }

    @Test("Testing the connection does not disturb a stored key")
    func testingLeavesAStoredKeyAlone() async {
        let item = KeychainItem.forTest("settings-test-keeps")
        defer { try? item.delete() }
        try? item.write("sk-stored")

        let model = SettingsModel(
            keychain: item,
            makeBackend: { _ in SettingsStubBackend(models: []) }
        )
        model.loadAPIKey()
        await model.testConnection()

        #expect((try? item.read()) == "sk-stored")
        #expect(model.hasStoredKey)
    }
}

// MARK: -

nonisolated extension KeychainItem {

    /// A keychain item for one test, under an account nothing else will use.
    ///
    /// The account carries a fresh UUID because the item's access control
    /// records the **code signature** of the process that created it, and every
    /// ad-hoc signed test build has a different one. An item left behind by a
    /// run that was interrupted is therefore unreadable to the next run's
    /// binary — macOS puts a password sheet in front of the read, the test
    /// blocks on it for as long as the timeout allows, and then fails for a
    /// reason that has nothing to do with what it was testing. That happened.
    static func forTest(_ name: String) -> KeychainItem {
        KeychainItem(
            service: "apps.levo-studio.Retain.tests",
            account: "\(name)-\(UUID().uuidString)"
        )
    }
}
