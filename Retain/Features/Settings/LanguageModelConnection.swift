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

/// What the API key row does with what was typed.
///
/// The key lives in the Keychain and is read exactly once per request, deep in
/// `LMStudioBackend`. It is **never** loaded into the field: a stored key is
/// reported as a placeholder that says a key is stored, and the field itself
/// stays empty until somebody types into it. That is the difference between a
/// secret that exists and a secret that is on screen.
nonisolated enum APIKeyField {

    /// What the empty field says.
    ///
    /// The export draws one placeholder, for the case where nothing is stored.
    /// The other is invented, because the export has no state for it.
    static func placeholder(hasStoredKey: Bool) -> String {
        hasStoredKey
            ? String(localized: "Stored in the Keychain — type to replace",
                     comment: "Placeholder of the API key field when a key is already stored")
            : String(localized: "leave empty for LM Studio",
                     comment: "Placeholder of the optional API key field")
    }

    /// What committing the field should do.
    enum Outcome: Equatable, Sendable {
        /// The field was not touched. Whatever is stored stays stored.
        case keep
        /// Store this, replacing anything already there.
        case store(String)
        /// The field was cleared. Remove the item.
        case remove
    }

    /// - Parameters:
    ///   - draft: exactly what is in the field.
    ///   - wasEdited: whether the user has typed into it since the pane opened.
    ///     An untouched empty field must not delete a stored key — the field is
    ///     empty because a stored key is never loaded into it.
    static func outcome(draft: String, wasEdited: Bool) -> Outcome {
        guard wasEdited else { return .keep }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .remove : .store(trimmed)
    }
}
