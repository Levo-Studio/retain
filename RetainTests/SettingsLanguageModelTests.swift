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

    @Test("An untouched field changes nothing, because a stored key is never in it")
    func untouchedFieldKeepsTheKey() {
        #expect(APIKeyField.outcome(draft: "", wasEdited: false) == .keep)
        #expect(APIKeyField.outcome(draft: "whatever", wasEdited: false) == .keep)
    }

    @Test("A cleared field removes the item")
    func clearedFieldRemoves() {
        #expect(APIKeyField.outcome(draft: "", wasEdited: true) == .remove)
        #expect(APIKeyField.outcome(draft: "   ", wasEdited: true) == .remove)
    }

    @Test("A typed key is stored trimmed")
    func typedKeyIsStored() {
        #expect(APIKeyField.outcome(draft: "  sk-abc  ", wasEdited: true) == .store("sk-abc"))
    }

    @Test("The placeholder says a key exists without saying what it is")
    func placeholderNeverShowsTheKey() {
        #expect(APIKeyField.placeholder(hasStoredKey: false) == "leave empty for LM Studio")
        let stored = APIKeyField.placeholder(hasStoredKey: true)
        #expect(stored == "Stored in the Keychain — type to replace")
        #expect(!stored.contains("sk-"))
    }

    /// The whole point of the field: the model reports *that* there is a key
    /// and never *what* it is.
    @Test("A stored key is never loaded back into the field")
    func storedKeyIsNeverEchoed() {
        let item = KeychainItem(service: "apps.levo-studio.Retain.tests", account: "settings-echo")
        defer { try? item.delete() }
        try? item.write("sk-live-should-never-be-drawn")

        let model = SettingsModel(keychain: item)

        #expect(model.hasStoredKey)
        #expect(model.apiKeyDraft.isEmpty)
        #expect(!model.apiKeyPlaceholder.contains("sk-live"))
    }

    @Test("Committing a typed key stores it and drops the draft")
    func committingStoresAndForgets() {
        let item = KeychainItem(service: "apps.levo-studio.Retain.tests", account: "settings-commit")
        defer { try? item.delete() }
        try? item.delete()

        let model = SettingsModel(keychain: item)
        model.apiKeyDraft = "sk-typed"
        model.commitAPIKey()

        #expect((try? item.read()) == "sk-typed")
        #expect(model.apiKeyDraft.isEmpty)
        #expect(model.hasStoredKey)

        // And committing again with the now-empty draft must not delete it.
        model.commitAPIKey()
        #expect((try? item.read()) == "sk-typed")
    }
}
