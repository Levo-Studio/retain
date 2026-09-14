import Foundation

// MARK: - The status line

/// What the line under the model picker says, and what its dot means.
///
/// A value with no view and no backend in it, so the four things it can say can
/// be read back in a test without a server anywhere near them.
///
/// **A failure carries the error's own message and nothing else.** No status
/// code dump, no response body, no URL — the base URL can carry a key in it if
/// the user pasted one there, and a message that echoes the address is a
/// message that leaks it into a screenshot.
nonisolated enum LanguageModelConnection: Equatable, Sendable {

    /// Opened the pane and has not pressed the button. The export draws no
    /// line at all in this state.
    case untested

    case testing

    case connected(ConnectionReport)

    /// `LocalizedError.errorDescription` of whatever was thrown.
    case failed(String)

    /// The line as drawn, or `nil` where the export draws no line.
    var message: String? {
        switch self {
        case .untested:
            nil
        case .testing:
            String(localized: "Testing …", comment: "Status line while the connection test is running")
        case .connected(let report):
            Self.connectedMessage(report)
        case .failed(let reason):
            reason
        }
    }

    /// "Connected · 3 models loaded · answered in 240 ms", as board 06 draws it.
    static func connectedMessage(_ report: ConnectionReport) -> String {
        let models = String(
            localized: "\(report.modelCount) models loaded",
            comment: "Middle part of the connected status line in settings"
        )
        return String(
            localized: "Connected · \(models) · answered in \(milliseconds(report.latency)) ms",
            comment: "Status line after a successful connection test"
        )
    }

    /// The round trip in whole milliseconds. The export writes "240 ms", never
    /// a fraction of one.
    static func milliseconds(_ latency: TimeInterval) -> Int {
        Int((latency * 1000).rounded())
    }

    /// Whether the line is drawn in the accent, which is the only colour the
    /// export gives it.
    var isGood: Bool {
        if case .connected = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - The base URL

/// Validation of what the Base URL field holds.
///
/// The field says `http://localhost:1234/v1` and keeps saying it — the client
/// swaps the path to `/api/v0/` itself, which is a settled decision and lives
/// in `LMStudioEndpoint`. This type only answers whether the typed address is
/// one Retain is allowed to open at all.
nonisolated enum BaseAddress {

    /// The address LM Studio serves on out of the box, which is what the field
    /// holds until somebody changes it.
    static var `default`: String { LMStudioEndpoint.defaultBaseAddress }

    /// `nil` when the address is usable, the reason otherwise.
    ///
    /// Hard rule 9 is the whole point: an address that is not this Mac is
    /// **refused**, not warned about. Retain has no network code beyond
    /// `localhost`, so a base URL pointing anywhere else is a setting that
    /// cannot be honoured.
    static func rejection(for address: String) -> String? {
        do {
            _ = try LMStudioEndpoint(address: address)
            return nil
        } catch let error as SummarizationError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    static func isAcceptable(_ address: String) -> Bool {
        rejection(for: address) == nil
    }

    /// The address as it may appear on screen.
    ///
    /// The "LM Studio is not responding" dialog names the URL, and the URL is a
    /// field the user types into: somebody who has been told to authenticate
    /// will paste `http://user:sk-live-…@localhost:1234/v1` sooner or later.
    /// Scheme, host, port and path are what the dialog is for; **user info, the
    /// query and the fragment are dropped**, because those are where a secret
    /// ends up.
    static func displayed(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return "" }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        return components.string ?? ""
    }
}

// MARK: - The model picker

/// What the model row reads when there is no model to read.
///
/// The export draws one state — a model chosen, `qwen3-14b-instruct · Q4_K_M`.
/// The other two happen every time somebody opens the pane before LM Studio is
/// running, so both lines below are invented.
nonisolated enum ModelPicker {

    static func label(selected: String, available: [LanguageModelDescriptor]) -> String {
        if available.isEmpty {
            return String(localized: "No models on the server",
                          comment: "Model picker label when the server listed nothing")
        }
        guard !selected.isEmpty else {
            return String(localized: "Choose a model",
                          comment: "Model picker label before a model has been chosen")
        }
        return selected
    }

    /// Whether the picker can be opened at all. A menu with no items is a menu
    /// that flashes open and shut.
    static func isEnabled(available: [LanguageModelDescriptor]) -> Bool {
        !available.isEmpty
    }

    /// Whether the label is drawn in placeholder ink rather than as a value.
    static func isPlaceholder(selected: String, available: [LanguageModelDescriptor]) -> Bool {
        available.isEmpty || selected.isEmpty
    }
}

// MARK: - The API key field

/// What the API key row says when it is empty.
///
/// The field **is** the Keychain item: what is stored is loaded into it when
/// the window opens and drawn as dots by a `SecureField`, and every change to
/// it is written straight back. So an empty field means one thing only — there
/// is no key — and the placeholder says exactly that.
///
/// It used to mean two things. A stored key was never loaded in, so an empty
/// field was either "no key" or "a key you cannot see", and the placeholder had
/// to explain which. That cost more than it bought: a key pasted into the field
/// was still a draft when the connection was tested, so the request went out
/// without it and LM Studio answered 401.
nonisolated enum APIKeyField {

    static var placeholder: String {
        String(localized: "leave empty for LM Studio",
               comment: "Placeholder of the optional API key field")
    }
}
