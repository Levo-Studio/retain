import Foundation

/// The three addresses Retain talks to, derived from the one the user typed.
///
/// The settings field holds `http://localhost:1234/v1`, because that is what LM
/// Studio prints when it starts and what the design draws in the Base URL
/// field. Retain nonetheless posts completions to `/api/v0/chat/completions`,
/// because only that route returns `stop_reason` and `loaded_context_length` —
/// the two numbers hard rule 13 and the context pre-flight are built on. Both
/// facts are true at once, and reconciling them is this type's whole job: the
/// stored value keeps saying `/v1` and the path is swapped here.
nonisolated struct LMStudioEndpoint: Hashable, Sendable {

    /// What LM Studio serves on out of the box.
    static let defaultBaseAddress = "http://localhost:1234/v1"

    /// The address as the user typed it, `/v1` and all.
    let base: URL

    /// - Throws: `SummarizationError.notLocalhost` for anything that is not
    ///   this Mac. Hard rule 9: Retain has no network code beyond `localhost`,
    ///   and the check belongs here rather than at the call site, because a
    ///   check at the call site is a check somebody forgets at the fourth one.
    init(base: URL) throws {
        guard let scheme = base.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw SummarizationError.notLocalhost
        }
        guard let host = base.host?.lowercased(), Self.localHosts.contains(host) else {
            throw SummarizationError.notLocalhost
        }
        self.base = base
    }

    /// Convenience for a stored setting, which is a string.
    init(address: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SummarizationError.notLocalhost
        }
        try self.init(base: url)
    }

    /// Every spelling of "this machine" that `URL` can hand back.
    ///
    /// `0.0.0.0` is deliberately not here. It means "every interface", which is
    /// what a server binds to, not what a client connects to — and a request
    /// sent to it is not guaranteed to stay on the machine.
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    // MARK: - Routes

    /// `GET /v1/models` — the list the settings picker is filled from.
    ///
    /// The OpenAI-compatible route on purpose: it is the one that lists every
    /// model the server has, loaded or not, which is what a picker needs.
    var models: URL {
        openAIRoot.appendingPathComponent("models")
    }

    /// `POST /api/v0/chat/completions`.
    var chatCompletions: URL {
        nativeRoot.appendingPathComponent("chat/completions")
    }

    /// `GET /api/v0/models/<id>` — where `loaded_context_length` comes from.
    func model(_ identifier: String) -> URL {
        nativeRoot.appendingPathComponent("models").appendingPathComponent(identifier)
    }

    // MARK: - Path arithmetic

    /// The base with any API prefix removed, so a user who pasted
    /// `http://localhost:1234`, `.../v1` or `.../v1/` all end up in one place.
    private var serverRoot: URL {
        var url = base
        while let last = url.pathComponents.last, last != "/" {
            if last == "v1" || last == "v0" || last == "api" {
                url = url.deletingLastPathComponent()
            } else {
                break
            }
        }
        return url
    }

    private var openAIRoot: URL {
        serverRoot.appendingPathComponent("v1")
    }

    private var nativeRoot: URL {
        serverRoot.appendingPathComponent("api").appendingPathComponent("v0")
    }
}
