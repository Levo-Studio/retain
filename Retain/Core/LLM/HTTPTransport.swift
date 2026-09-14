import Foundation

/// The one place a request actually leaves the process.
///
/// Extracted from `LMStudioBackend` so the client can be driven from recorded
/// replies in tests. That is not a convenience: a client tested against a live
/// LM Studio is a client that is only tested on a machine which happens to be
/// running one, and the three interesting cases — a malformed answer, a server
/// that rejects `json_schema`, a stop reason that says the model was cut off —
/// are exactly the ones a healthy live server never produces.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real one.
nonisolated struct URLSessionTransport: HTTPTransport {

    let session: URLSession

    /// A session that keeps nothing.
    ///
    /// Ephemeral on purpose: there is no cache, no cookie jar and no credential
    /// store for a transcript to be left in. The prompt carries the recording, and
    /// nothing about the recording may outlive the request.
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false

        // A reduce over a ninety-minute recording on a large model can genuinely
        // take minutes on a laptop. The timeout is for a server that is gone,
        // not for one that is thinking.
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 1800

        // Nothing here has any business finding a proxy: the destination is
        // this machine.
        configuration.connectionProxyDictionary = [:]

        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SummarizationError.unreachable
            }
            return (data, http)
        } catch let error as SummarizationError {
            throw error
        } catch {
            // Deliberately not carrying the underlying error's text any
            // further. It names hosts and ports, and it ends up in a dialog.
            throw SummarizationError.unreachable
        }
    }
}
