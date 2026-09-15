import Defaults
import Foundation
import GRDB
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

    /// What is in the API key field — and, as soon as it changes, what is in
    /// the Keychain.
    ///
    /// It used to be a draft that was written on Return, on losing focus, or
    /// when the window closed, and cleared afterwards so that no secret sat in
    /// an observable property. That was wrong twice over: a key pasted and then
    /// tested went out as no key at all, and a field that empties itself the
    /// moment you look away is indistinguishable from one that threw your input
    /// away.
    ///
    /// So the field is the item. Typing or pasting writes through to the
    /// Keychain immediately, clearing it removes the item, and what is stored
    /// is loaded back in when the window opens — as dots, in a `SecureField`.
    /// Hard rule 10 is about where the key is **kept**, and it still is: the
    /// Keychain, never `UserDefaults`.
    var apiKeyDraft: String {
        get { apiKeyText }
        set {
            guard newValue != apiKeyText else { return }
            // Typing into the field counts as having read it: whatever was
            // stored is being replaced by this, so there is nothing left to
            // load over the top of it.
            hasLoadedAPIKey = true
            apiKeyText = newValue
            storeAPIKey()
        }
    }

    private var apiKeyText = ""

    private(set) var hasStoredKey = false

    /// Whether the Keychain has been read yet. See `init` — it deliberately
    /// has not been at launch.
    private var hasLoadedAPIKey = false

    /// Why the last write to the Keychain failed, drawn under the field.
    ///
    /// The write used to be `try?` with `hasStoredKey = true` after it
    /// regardless, so a Keychain that refused the item still reported the key
    /// as stored while every request went out without it.
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

    /// What the backend reads the key out of. `nil` in a test with its own
    /// keychain item, so a test never writes into the process-wide cache the
    /// real app shares.
    private let keyCache: LanguageModelKey?

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
        keyCache: LanguageModelKey? = .shared,
        makeBackend: @escaping @MainActor (LMStudioEndpoint) -> any SummarizationBackend = { LMStudioBackend(endpoint: $0) }
    ) {
        self.speechModels = speechModels
        self.recorder = recorder
        self.library = library
        self.keychain = keychain
        self.keyCache = keychain == RetainKeychain.languageModelAPIKey ? keyCache : nil
        self.makeBackend = makeBackend

        section = Defaults[.settingsSection]
        address = Defaults[.languageModelAddress]
        selectedModel = Defaults[.languageModelName]
        // **The Keychain is not read here.** This model is built while the app
        // is launching, and a Keychain read from a build whose signature the
        // item does not know puts a system password sheet on screen — which,
        // during launch, is a sheet in front of an app that has not finished
        // starting. It hung the test host for five minutes before it was
        // traced back to here.
        //
        // Nothing needs the key until the pane that shows it is open, so the
        // read waits for `loadAPIKey()`.
    }

    // MARK: - The connection test

    /// Asks the backend whether anybody is listening, and refills the picker
    /// when somebody is.
    func testConnection() async {
        guard !isTesting else { return }

        // A write that had failed gets one more attempt before the request,
        // so a test does not go out without a key the user believes is stored.
        // The field itself is already in the Keychain by now — it is written
        // as it is typed.
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

    /// Writes the field to the Keychain, or removes the item when it is empty.
    ///
    /// Runs on every change to the field, so pasting a token stores it there
    /// and then. Nothing is deferred to Return, to losing focus or to the
    /// window closing — each of those was a moment the user had no reason to
    /// expect, and the connection test in between went out with no key.
    /// Reads the stored key into the field, once, when the pane opens.
    ///
    /// The stored key is loaded rather than hidden behind a placeholder: it is
    /// drawn as dots by a `SecureField`, and a field that shows nothing while a
    /// key exists cannot be told apart from one that lost it.
    func loadAPIKey() {
        guard !hasLoadedAPIKey else { return }
        hasLoadedAPIKey = true

        do {
            apiKeyText = try keychain.read() ?? ""
            hasStoredKey = !apiKeyText.isEmpty
            // One read, shared: the pane and the backend now ask the same
            // cache, so opening Settings does not cost a second prompt.
            keyCache?.replace(with: apiKeyText.isEmpty ? nil : apiKeyText)
            apiKeyProblem = nil
        } catch {
            apiKeyProblem = Self.message(for: error)
        }
    }

    private func storeAPIKey() {
        let trimmed = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try keychain.delete()
                hasStoredKey = false
            } else {
                try keychain.write(trimmed)
                hasStoredKey = true
            }
            // The backend reads the key once per launch and holds it, so a key
            // changed here has to be handed over rather than left for a read
            // that will not happen again.
            keyCache?.replace(with: trimmed.isEmpty ? nil : trimmed)
            apiKeyProblem = nil
        } catch {
            apiKeyProblem = Self.message(for: error)
        }
    }

    /// Kept for the places that used to commit a draft — the window closing,
    /// Return in the field. The field is already stored by then, so this only
    /// catches a write that had failed.
    func commitAPIKey() {
        guard apiKeyProblem != nil else { return }
        storeAPIKey()
    }

    var apiKeyPlaceholder: String { APIKeyField.placeholder }

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

    /// Follows the library for as long as the pane is open.
    ///
    /// The General pane is one of the two places a term or a course is created,
    /// and the library window is the other. Without this, each of them showed
    /// its own idea of the list until Retain was quit.
    func followLibrary() async {
        guard let library else { return }
        do {
            for try await _ in library.changes {
                await loadLibrary()
            }
        } catch {
            await loadLibrary()
        }
    }

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
