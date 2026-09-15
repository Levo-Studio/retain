import Defaults
import Foundation
import Observation

/// Whether the language model is there, and whether it is ready to answer.
///
/// **Retain had no word for this at all.** The model was reached only when
/// something needed it — a block closing during a lecture, a question in the
/// chat — and until then nobody knew whether LM Studio was running, whether the
/// chosen model existed, or whether it was in memory. The first summary of a
/// lecture then waited twenty seconds for a 20B model to be read off disk, and
/// a waiting Retain and a broken Retain looked exactly the same.
///
/// So the state is asked for up front and kept: on launch, and again whenever
/// the address or the model changes. The model is also **loaded** up front,
/// because a load that happens during the first block is a lecture whose first
/// note arrives late for no reason the user can see.
@MainActor
@Observable
final class LanguageModelPresence {

    /// The one the app shares. The recording window, the detail window and the
    /// popover all draw the same answer, because there is one server.
    static let shared = LanguageModelPresence()

    nonisolated enum Status: Equatable, Sendable {
        /// No model has been chosen yet — the ordinary state of a fresh
        /// install, and not an error.
        case notConfigured
        /// Asking the server.
        case checking
        /// The server answered and the model is being read into memory.
        case loading(String)
        /// Ready to answer. Carries the context it was actually loaded with,
        /// which is routinely not the context the model advertises.
        case ready(model: String, context: Int?)
        /// Reachable, but the chosen model is not among the ones it offers.
        case modelMissing(String)
        /// The server said nothing usable. Carries the error's own words.
        case unreachable(String)
    }

    private(set) var status: Status = .notConfigured

    /// So a second caller does not start a second load of the same model.
    private var work: Task<Void, Never>?

    private let makeBackend: @MainActor (LMStudioEndpoint) -> any SummarizationBackend

    init(makeBackend: @escaping @MainActor (LMStudioEndpoint) -> any SummarizationBackend = { LMStudioBackend(endpoint: $0) }) {
        self.makeBackend = makeBackend
    }

    // MARK: -

    /// Asks the server what it has, and loads the chosen model if it is cold.
    ///
    /// Safe to call as often as anything likes: a run already in flight is
    /// joined rather than duplicated.
    func refresh(loadingIfCold: Bool = true) {
        if let work {
            Task { await work.value }
            return
        }

        let model = Defaults[.languageModelName]
        let address = Defaults[.languageModelAddress]

        guard !model.isEmpty else {
            status = .notConfigured
            return
        }
        guard let endpoint = try? LMStudioEndpoint(address: address) else {
            status = .unreachable(BaseAddress.rejection(for: address) ?? "")
            return
        }

        status = .checking
        let backend = makeBackend(endpoint)

        work = Task { [weak self] in
            defer { self?.work = nil }
            await self?.run(backend, model: model, loadingIfCold: loadingIfCold)
        }
    }

    private func run(_ backend: any SummarizationBackend, model: String, loadingIfCold: Bool) async {
        let models: [LanguageModelDescriptor]
        do {
            models = try await backend.availableModels()
        } catch {
            status = .unreachable(SettingsModel.message(for: error))
            return
        }

        guard let chosen = models.first(where: { $0.id == model }) else {
            status = .modelMissing(model)
            return
        }

        if chosen.state == .loaded {
            status = .ready(model: model, context: chosen.contextLength)
            return
        }

        guard loadingIfCold else {
            status = .loading(model)
            return
        }

        status = .loading(model)
        do {
            try await backend.load(model)
        } catch {
            status = .unreachable(SettingsModel.message(for: error))
            return
        }

        // Asked again rather than assumed: the load succeeded, and the context
        // it was loaded with is the number everything downstream measures
        // against.
        let context = try? await backend.loadedContextLength(of: model)
        status = .ready(model: model, context: context)
    }
}
