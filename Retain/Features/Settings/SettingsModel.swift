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
        didSet {
            // **Only an address Retain may actually open is stored.** It used
            // to store whatever was typed, so a half-finished address — or one
            // pointing somewhere that is not this Mac, which hard rule 9
            // refuses outright — replaced a working `http://localhost:1234/v1`
            // in `UserDefaults` and stayed there after the window closed.
            // Every request then failed at the endpoint before it was even
            // built, and nothing said why: the field showed the reason while it
            // was open, and the next launch showed a working-looking app with
            // no connection.
            //
            // The field keeps what was typed — it has to, or it could not be
            // edited — and the rejection under it says why it is not being
            // used.
            guard BaseAddress.isAcceptable(address) else { return }
            Defaults[.languageModelAddress] = address
            // The pill in three windows is showing what the old address said.
            LanguageModelPresence.shared.refresh()
        }
    }

    /// `nil` while the address is one Retain may open, the reason otherwise.
    var addressRejection: String? { BaseAddress.rejection(for: address) }

    var selectedModel: String {
        didSet {
            Defaults[.languageModelName] = selectedModel
            // Choosing a model is the moment to start reading it into memory,
            // rather than the first block of the next lecture.
            LanguageModelPresence.shared.refresh()
        }
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
        // **A server that did not answer is not a server with no models.**
        // This used to clear the chosen model whenever the list came back
        // empty, which is exactly what an unreachable server, a wrong address
        // or a missing API key produce. One 401 and a model the user had
        // chosen weeks ago was gone from `UserDefaults`, the title bar said
        // "No model", and nothing connected the two.
        guard !availableModels.isEmpty else { return }

        if availableModels.contains(where: { $0.id == selectedModel }) { return }
        // A server with exactly one model needs no decision; with several, the
        // old choice is not among them and there is nothing honest to pick.
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

    /// Reads the stored key into the field, once, when the pane opens.
    ///
    /// The stored key is loaded rather than hidden behind a placeholder: drawn
    /// as dots by a `SecureField`, and a field that shows nothing while a key
    /// exists cannot be told apart from one that lost it.
    ///
    /// **`hasLoadedAPIKey` is set only when the read succeeded**, and that is
    /// the whole point of it. An empty field means two different things — "you
    /// have no key" and "your key could not be read" — and the code that
    /// deleted the item could not tell them apart. A read that failed (a
    /// Keychain the user declined, a signature it did not recognise) left the
    /// field empty, and the next write took that emptiness at face value and
    /// removed the item. It deleted a real key off a real machine.
    func loadAPIKey() {
        guard !hasLoadedAPIKey else { return }

        do {
            // Through the shared cache where there is one, so opening the pane
            // costs no access of its own: on a build whose signature the item
            // does not recognise, every access is its own password sheet, and
            // this used to be a second one on top of the backend's.
            // Through the shared cache where there is one, which leaves the
            // Keychain alone entirely when nothing was ever stored.
            if let keyCache {
                apiKeyText = keyCache.value() ?? ""
            } else {
                apiKeyText = try keychain.read() ?? ""
            }
            hasStoredKey = !apiKeyText.isEmpty
            hasLoadedAPIKey = true
            apiKeyProblem = nil
        } catch {
            // Deliberately still `false`. The field does not mirror the item,
            // so nothing typed into it may remove the item.
            apiKeyProblem = Self.message(for: error)
        }
    }

    /// Writes what is in the field to the Keychain.
    ///
    /// Runs on every change, so pasting a token stores it there and then —
    /// nothing is deferred to Return, to losing focus or to the window closing,
    /// each of which was a moment the user had no reason to expect and the
    /// connection test in between went out with no key.
    private func storeAPIKey() {
        let trimmed = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmed.isEmpty {
                // **Only when the field is known to mirror the item.** An empty
                // field whose read failed says nothing about what is stored,
                // and acting on it is how a key gets deleted by an app that was
                // only trying to display it.
                guard hasLoadedAPIKey else { return }
            } else {
                // What is in the field is now what is stored, whatever the read
                // did or did not manage earlier.
                hasLoadedAPIKey = true
            }

            if let keyCache {
                try keyCache.write(trimmed)
            } else {
                if trimmed.isEmpty { try keychain.delete() } else { try keychain.write(trimmed) }
            }
            hasStoredKey = !trimmed.isEmpty
            apiKeyProblem = nil
        } catch {
            apiKeyProblem = Self.message(for: error)
        }
    }

    /// Retries a write that failed, for the places that used to commit a draft:
    /// Return in the field, and the window closing.
    ///
    /// It never deletes. A retry is for a key somebody typed that did not make
    /// it into the Keychain; an empty field here is not an instruction.
    func commitAPIKey() {
        guard apiKeyProblem != nil else { return }
        guard !apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
