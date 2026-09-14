import Defaults
import Foundation
import Observation

/// What the settings window is bound to.
///
/// It owns the settings themselves and nothing else: the microphone engine, the
/// speech models and the library are handed in, because the window is not where
/// any of them are created and a settings pane that constructs a
/// `RecordingEngine` would open the microphone to draw a meter.
///
/// **No request is built here.** Hard rule: there is no network code outside
/// `Core/LLM/`, so the connection test asks a `SummarizationBackend` and the
/// backend decides what a request looks like. That is also what lets the test
/// below run against a recorded reply instead of a server.
@MainActor
@Observable
final class SettingsModel {

    // MARK: - Which pane

    var section: SettingsSection {
        didSet { Defaults[.settingsSection] = section }
    }

    // MARK: - Language model

    var address: String {
        didSet { Defaults[.languageModelAddress] = address }
    }

    /// `nil` while the address is one Retain may open, the reason otherwise.
    var addressRejection: String? { BaseAddress.rejection(for: address) }

    var selectedModel: String {
        didSet { Defaults[.languageModelName] = selectedModel }
    }

    private(set) var availableModels: [LanguageModelDescriptor] = []

    private(set) var connection: LanguageModelConnection = .untested

    private(set) var isTesting = false

    /// What is typed into the API key field. **Never what is stored.** A key in
    /// the Keychain is reported through `hasStoredKey` and reaches the field
    /// only as a placeholder saying that it exists.
    var apiKeyDraft: String {
        get { apiKeyText }
        set {
            apiKeyText = newValue
            apiKeyWasEdited = true
        }
    }

    /// Written through rather than set directly, so that clearing the draft
    /// after a commit does not count as an edit and re-arm the removal.
    private var apiKeyText = ""

    private(set) var apiKeyWasEdited = false

    private(set) var hasStoredKey = false

    /// Why the last attempt to store the key failed, drawn under the field.
    ///
    /// The write used to be `try?` with `hasStoredKey = true` after it
    /// regardless, so a keychain that refused the item still flipped the
    /// placeholder to "Stored in the Keychain" — the field then said the key
    /// was saved while every request went out without it.
    private(set) var apiKeyProblem: String?

    // MARK: - Handed in

    let speechModels: SpeechModels?
    let recorder: RecordingEngine?
    let library: LibraryRepository?

    /// Builds the backend for an address. Injected so a test can answer without
    /// a server; in the app it is the LM Studio client and nothing else.
    private let makeBackend: @MainActor (LMStudioEndpoint) -> any SummarizationBackend

    /// Reads and writes the one Keychain item. Injected for the same reason —
    /// a test process has its own keychain and should not be writing to the
    /// user's.
    private let keychain: KeychainItem

    // MARK: - General

    private(set) var terms: [Term] = []
    private(set) var courses: [CourseListing] = []
    var selectedTermID: Int64?

    var selectedTerm: Term? {
        terms.first { $0.id == selectedTermID }
    }

    // MARK: -

    init(
        speechModels: SpeechModels? = nil,
        recorder: RecordingEngine? = nil,
        library: LibraryRepository? = nil,
        keychain: KeychainItem = RetainKeychain.languageModelAPIKey,
        makeBackend: @escaping @MainActor (LMStudioEndpoint) -> any SummarizationBackend = { LMStudioBackend(endpoint: $0) }
    ) {
        self.speechModels = speechModels
        self.recorder = recorder
        self.library = library
        self.keychain = keychain
        self.makeBackend = makeBackend

        section = Defaults[.settingsSection]
        address = Defaults[.languageModelAddress]
        selectedModel = Defaults[.languageModelName]
        hasStoredKey = (try? keychain.read()) != nil
    }

    // MARK: - The connection test

    /// Asks the backend whether anybody is listening, and refills the picker
    /// when somebody is.
    func testConnection() async {
        guard !isTesting else { return }

        // The key is stored before the request rather than after the window
        // closes. Somebody who pastes a token and presses Test has said what
        // they want the test to use; without this the field was still a draft,
        // the request went out with no `Authorization` header, and the server
        // answered 401 — which reads as "the key is wrong" when the key had
        // simply never been sent.
        commitAPIKey()

        isTesting = true
        connection = .testing
        defer { isTesting = false }

        do {
            let backend = makeBackend(try LMStudioEndpoint(address: address))
            let report = try await backend.checkConnection()
            connection = .connected(report)
            availableModels = (try? await backend.availableModels()) ?? []
            adoptModelIfNeeded()
        } catch {
            availableModels = []
            connection = .failed(Self.message(for: error))
        }
    }

    /// Fills the picker without changing the status line — what opening the
    /// pane does.
    func refreshModels() async {
        guard let endpoint = try? LMStudioEndpoint(address: address) else {
            availableModels = []
            return
        }
        availableModels = (try? await makeBackend(endpoint).availableModels()) ?? []
        adoptModelIfNeeded()
    }

    /// Keeps the picker honest: a stored model the server no longer has is not
    /// a selection, and a server with exactly one model needs no decision.
    private func adoptModelIfNeeded() {
        if availableModels.contains(where: { $0.id == selectedModel }) { return }
        selectedModel = availableModels.count == 1 ? (availableModels.first?.id ?? "") : ""
    }

    /// What a thrown error is allowed to say on screen.
    ///
    /// The error's own message, and never more than that. No status line
    /// carries a URL — the address field can hold a key if somebody pasted one
    /// into it — and none carries a response body, which is a transcript of
    /// somebody's recording coming back the other way.
    static func message(for error: any Error) -> String {
        if let summarization = error as? SummarizationError {
            return summarization.errorDescription ?? SummarizationError.unreachable.errorDescription ?? ""
        }
        if error is URLError {
            // URLSession's own text for a refused connection names the scheme
            // and sometimes the host. The design already has a sentence for
            // exactly this case, so it is used instead.
            return SummarizationError.unreachable.errorDescription ?? ""
        }
        return error.localizedDescription
    }

    // MARK: - The API key

    /// Writes what was typed, or removes the item if the field was cleared.
    ///
    /// Called when the field loses focus or the pane closes. An untouched field
    /// changes nothing: it is empty because a stored key is never loaded into
    /// it, not because there is no key.
    func commitAPIKey() {
        switch APIKeyField.outcome(draft: apiKeyDraft, wasEdited: apiKeyWasEdited) {
        case .keep:
            return
        case .store(let key):
            do {
                try keychain.write(key)
            } catch {
                // Kept in the field on purpose. Dropping a draft that was
                // never stored loses what the user typed and leaves the pane
                // claiming a key that is not there.
                apiKeyProblem = Self.message(for: error)
                return
            }
            hasStoredKey = true
            apiKeyProblem = nil
        case .remove:
            do {
                try keychain.delete()
            } catch {
                apiKeyProblem = Self.message(for: error)
                return
            }
            hasStoredKey = false
            apiKeyProblem = nil
        }
        // The draft is dropped the moment it has been stored, so the secret is
        // not sitting in an observable property for the rest of the session.
        apiKeyText = ""
        apiKeyWasEdited = false
    }

    var apiKeyPlaceholder: String { APIKeyField.placeholder(hasStoredKey: hasStoredKey) }

    // MARK: - Microphone

    var preferredInputUID: String? {
        get { recorder?.preferredDeviceUID ?? Defaults[.preferredInputDeviceUID] }
        set {
            Defaults[.preferredInputDeviceUID] = newValue
            recorder?.preferredDeviceUID = newValue
        }
    }

    var inputDevices: [InputDevice] { recorder?.devices ?? [] }

    var level: AudioLevel { recorder?.level ?? .silent }

    private(set) var authorization: MicrophoneAuthorization = MicrophoneAccess.authorization

    func refreshAuthorization() {
        authorization = MicrophoneAccess.authorization
    }

    func requestMicrophoneAccess() async {
        authorization = await MicrophoneAccess.request()
    }

    // MARK: - General

    func loadLibrary() async {
        guard let library else { return }
        terms = (try? await library.terms()) ?? []
        if selectedTermID == nil || !terms.contains(where: { $0.id == selectedTermID }) {
            selectedTermID = (try? await library.currentTerm())?.id ?? terms.first?.id
        }
        await loadCourses()
    }

    func loadCourses() async {
        guard let library, let termID = selectedTermID else {
            courses = []
            return
        }
        courses = (try? await library.courses(in: termID)) ?? []
    }

    /// Changes what the selected term is a term *of*.
    ///
    /// Per term rather than per app: somebody who changes school keeps the
    /// half-years they already recorded as half-years instead of having them
    /// silently re-labelled.
    func setTermKind(_ kind: TermKind) async {
        guard let library, var term = selectedTerm, term.kind != kind else { return }
        term.kind = kind
        _ = try? await library.save(term)
        await loadLibrary()
    }
}
