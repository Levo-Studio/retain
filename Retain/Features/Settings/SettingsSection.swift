import Foundation

/// The five rows of the settings sidebar, in the order board 06 draws them.
///
/// `CaseIterable` is what the sidebar is built from, so the order here is the
/// order on screen and there is no second list to keep in step.
nonisolated enum SettingsSection: String, CaseIterable, Hashable, Sendable, Identifiable {

    case general
    case languageModel
    case speechRecognition
    case microphone
    case shortcuts

    var id: String { rawValue }

    /// The sidebar label.
    var title: String {
        switch self {
        case .general:
            String(localized: "General", comment: "Settings section heading and sidebar row")
        case .languageModel:
            String(localized: "Language model", comment: "Settings section heading and sidebar row")
        case .speechRecognition:
            String(localized: "Speech recognition", comment: "Settings section heading and sidebar row")
        case .microphone:
            String(localized: "Microphone", comment: "Settings section heading and sidebar row, and the label above the permission dialog title")
        case .shortcuts:
            String(localized: "Shortcuts", comment: "Settings section heading and sidebar row")
        }
    }
}
