import AppKit
import SwiftUI

/// The language model's state, in the title bar of every window that depends on
/// it.
///
/// Not on any board — the export draws the model only in Settings, shut, with
/// a "Test connection" button beside it. That is enough when the question is
/// "is it configured" and not enough for the question a lecture actually asks,
/// which is "is it going to answer". A 20B model takes twenty seconds to read
/// off disk, and a Retain waiting for that and a Retain that will never answer
/// looked exactly the same.
///
/// It is drawn as the title bar's own pill — the shape the library's term
/// picker already uses — so it reads as part of the bar rather than as a
/// warning stuck to it.
struct ModelStatusPill: View {

    var presence: LanguageModelPresence = .shared

    /// Opens Settings, for the states the user can do something about.
    ///
    /// Through the responder chain rather than a closure every window would
    /// have to be handed: the application menu's own Settings item reaches the
    /// delegate exactly this way, and a pill in three windows should not mean
    /// three pieces of plumbing.
    var openSettings: () -> Void = {
        NSApp.sendAction(#selector(RetainApp.openSettings(_:)), to: nil, from: nil)
    }

    var body: some View {
        Button {
            switch presence.status {
            case .notConfigured, .modelMissing, .unreachable:
                openSettings()
            case .checking, .loading, .ready:
                // Already doing the only useful thing, or already done.
                presence.refresh()
            }
        } label: {
            HStack(spacing: RetainMetrics.titleBarPillGap) {
                RetainStatusDot(colour: dot, diameter: RetainMetrics.statusDotSmall)

                Text(verbatim: label)
                    .retainStyle(RetainTypography.titleBarTermPill)
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
            .padding(.trailing, RetainMetrics.titleBarPillGap)
        }
        .buttonStyle(
            RetainSecondaryButtonStyle(
                textStyle: RetainTypography.titleBarTermPill,
                padding: RetainMetrics.titleBarPillPadding,
                cornerRadius: RetainMetrics.radiusStatusPill,
                isFilled: true
            )
        )
        .fixedSize()
        .help(help)
        .task { presence.refresh() }
    }

    // MARK: - What it says

    private var label: String {
        switch presence.status {
        case .notConfigured: ModelStatusCopy.notConfigured
        case .checking: ModelStatusCopy.checking
        case .loading(let model): ModelStatusCopy.loading(model)
        case .ready(let model, _): model
        case .modelMissing(let model): ModelStatusCopy.missing(model)
        case .unreachable: ModelStatusCopy.unreachable
        }
    }

    /// The full sentence, where the pill only has room for a word. A failure's
    /// own message can be a paragraph and the bar is a bar.
    private var help: String {
        if case .unreachable(let reason) = presence.status, !reason.isEmpty { return reason }
        if case .ready(_, let context) = presence.status, let context {
            return ModelStatusCopy.readyWithContext(context)
        }
        return label
    }

    private var dot: Color {
        switch presence.status {
        case .ready: RetainPalette.accent
        // Amber is what the export already uses for work in progress — the
        // status dot while a recording is being summarised.
        case .checking, .loading: RetainPalette.amber
        case .unreachable, .modelMissing: RetainPalette.redError
        case .notConfigured: RetainPalette.inkLabel
        }
    }

    private var ink: Color {
        switch presence.status {
        case .unreachable, .modelMissing: RetainPalette.redInk
        case .notConfigured: RetainPalette.inkLabel
        default: RetainPalette.inkPrimary
        }
    }
}

// MARK: -

nonisolated enum ModelStatusCopy {

    static var notConfigured: String {
        String(localized: "No model", comment: "Model status in the title bar before a model has been chosen")
    }

    static var checking: String {
        String(localized: "Checking …", comment: "Model status while the server is being asked")
    }

    static func loading(_ model: String) -> String {
        String(localized: "Loading \(model) …", comment: "Model status while the server reads the model into memory")
    }

    static func missing(_ model: String) -> String {
        String(localized: "\(model) is not on the server", comment: "Model status when the chosen model is not one the server offers")
    }

    static var unreachable: String {
        String(localized: "No model connection", comment: "Model status when the server could not be reached")
    }

    static func readyWithContext(_ context: Int) -> String {
        String(localized: "Loaded with room for \(context) tokens",
               comment: "Model status tooltip naming the context the model was loaded with")
    }
}
